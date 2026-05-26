# Tap Screen Tap — Windows Specification

A complete behavioral and UI specification for porting the existing Android "Tap Screen Tap" auto-tapper to Windows. This document is exhaustive on purpose: feed it whole to an AI agent or a developer and they should be able to build the app without referring back to the Android codebase.

---

## 1. Product overview

Tap Screen Tap is a desktop auto-tapper. The user defines **scripts**, each a list of ordered **tap steps** plus a small set of timing/randomness settings. The user picks one active script, opens a small always-on-top **control island**, and starts/stops execution from there. Taps are dispatched as synthetic mouse clicks targeting absolute screen coordinates, even when the user has other applications focused.

Two foreground surfaces exist while the app is running:

1. **Main window** — script management, logs, settings.
2. **Floating control island** — small, draggable, always-on-top window with Start / Stop / Record buttons and the active script's name.

A third transient surface appears while recording:

3. **Fullscreen recorder overlay** — covers the entire display(s) of the active monitor, lets the user tap to add markers, drag to move them, undo, save, cancel.

The original Android version runs taps via the AccessibilityService and dispatches `GestureDescription`s. The Windows version dispatches taps via `SendInput` (or `mouse_event` as a fallback) with absolute screen coordinates.

---

## 2. Recommended tech stack

The reference implementation is Flutter (Dart) for the cross-platform UI plus Kotlin for native Android. For Windows, the recommended choices are:

| Layer | Primary recommendation | Alternative |
|---|---|---|
| UI framework | **Flutter for Windows** (so the same Dart UI code can be reused; only the platform channel changes) | WinUI 3 / Electron / Avalonia / Tauri |
| Native plugin | Win32 in C++ via the Flutter Windows plugin template | Rust via `windows` crate (with Tauri/Avalonia) |
| Persistence | `shared_preferences_windows` (writes to JSON in `%APPDATA%`) | A simple JSON file managed manually |
| Build/distribution | MSIX package signed with a code-signing cert | NSIS / Inno Setup / .zip |
| Min Windows | Windows 10 1809 (build 17763) | — |

Reuse from the Flutter codebase is direct: the Dart UI, models, repositories, the script editor, the logs screen, and the click "controller" logic can all be reused with a different platform channel implementation. Replace the Android-specific bits (accessibility service, overlay window, gesture dispatch) with the Windows equivalents described below.

If the user prefers a non-Flutter stack, the spec is framework-agnostic — every UI surface, behavior, and data structure is described in detail.

---

## 3. Glossary

- **Step** / **Tap step**: a single point `(x, y)` with optional per-step delay and per-step radius override.
- **Script**: an ordered list of steps plus global settings (delays, randomness, run mode, name).
- **Active script**: the script the user has selected via the toggle in the scripts list; the island always reflects this.
- **Run mode**: either "until stopped" (loops forever) or "iterations" (N times then stops).
- **Iteration**: one full pass over all steps in the script.
- **Tap randomness**: when enabled, each tap is jittered by a uniformly-random offset inside a circle of radius `radiusPx`.
- **Global radius**: the default radius applied when tap randomness is on and the step doesn't specify its own override.
- **Default delay range** (`defaultMinDelayMs`, `defaultMaxDelayMs`): the delay applied after a step when the step does not specify its own delay. A uniform random integer in `[min, max]`.
- **Global random delay**: when enabled, adds a uniform random `0..globalMaxRandomDelaySec` seconds on top of every per-step delay (including end-of-iteration delay).
- **End delay**: a delay applied after each full iteration (before the next iteration starts).
- **Control island**: small floating always-on-top window with Start/Stop/Record.
- **Recorder**: fullscreen overlay used to place/move/delete steps visually.
- **Stop reason** (in logs): one of `user_stopped`, `iterations_done`, `error`, `running` (in-progress).

---

## 4. Data model

All persisted data is plain JSON. The exact schema must match the table below so script files can be hand-edited or imported/exported across platforms.

### 4.1 `TapStep`

| Field | Type | Required | Notes |
|---|---|---|---|
| `x` | number (double) | yes | Absolute physical-screen X coordinate, virtual desktop space (see §6.1). |
| `y` | number (double) | yes | Absolute physical-screen Y coordinate, virtual desktop space (see §6.1). |
| `delayAfterMs` | int | no | If set, this delay is used after this step instead of the default range. `null`/omitted = use range. |
| `radiusPx` | int | no | If set, overrides `globalRadiusPx` for this step. `null`/omitted = use global. |

JSON example:

```json
{ "x": 1234.0, "y": 567.0, "delayAfterMs": 1500, "radiusPx": 8 }
```

### 4.2 `RunMode`

| Field | Type | Notes |
|---|---|---|
| `type` | `"untilStopped"` \| `"iterations"` | |
| `count` | int | Used only for `iterations`. Must be `>= 1`. Defaults to `1`. |

### 4.3 `Script`

| Field | Type | Default | Notes |
|---|---|---|---|
| `id` | string (UUID v4) | — | Stable identifier; never reused. |
| `name` | string | "New Script" | Free-form; must be non-empty on save. |
| `steps` | `TapStep[]` | `[]` | Ordered. |
| `tapRandomnessEnabled` | bool | `false` | When true, taps are jittered. |
| `globalRadiusPx` | int | `15` | Pixels. `0` disables jitter even when `tapRandomnessEnabled` is true. |
| `defaultMinDelayMs` | int | `1000` | |
| `defaultMaxDelayMs` | int | `3000` | If `min >= max`, the engine uses `min` exactly (no random pick). |
| `globalRandomDelayEnabled` | bool | `false` | Adds random seconds to every delay. |
| `globalMaxRandomDelaySec` | int | `3` | Cap for the global random add-on (in seconds). |
| `endDelayMs` | int | `0` | Applied after each full iteration. `0` disables. |
| `runMode` | `RunMode` | `untilStopped` | |

### 4.4 `LogEntry`

| Field | Type | Notes |
|---|---|---|
| `timestamp` | ISO 8601 string | |
| `type` | enum (see below) | |
| `data` | object | Free-form payload, depends on type. |

`type` values: `runStarted`, `iterationStarted`, `tapPerformed`, `delayApplied`, `iterationCompleted`, `runEnded`, `error`.

Per-type payload contents:

- `runStarted` — `{ scriptName, iterationsRequested, stepCount }`. `iterationsRequested = -1` means "until stopped".
- `iterationStarted` — `{ iteration }` (1-based).
- `tapPerformed` — `{ stepIndex, definedX, definedY, actualX, actualY, radiusPx, jitterApplied, gestureSuccess }`.
- `delayApplied` — `{ stepIndex, baseDelayMs, randomAddonMs, totalDelayMs, source }`. `stepIndex = -1` means end-of-iteration delay. `source` is `"perStep" | "defaultRange" | "endDelay"`.
- `iterationCompleted` — `{ iteration }`.
- `runEnded` — `{ totalTaps, totalDurationMs, stopReason, iterationsCompleted, iterationsRequested }`.
- `error` — `{ message, stepIndex? }`.

### 4.5 `ExecutionLog`

One log is stored **per script** (keyed by `scriptId`). Each new run **overwrites** the previous log for the same script. This is intentional and matches the Android version — the Logs tab shows the most recent run only.

| Field | Type | Notes |
|---|---|---|
| `scriptId` | string | |
| `scriptName` | string | Snapshot at run start. |
| `startedAt` | ISO 8601 | |
| `endedAt` | ISO 8601 \| null | Null while running. |
| `stopReason` | string | `running` while in-progress, then one of the run-ended values. |
| `iterationsRequested` | int | `-1` = until stopped. |
| `iterationsCompleted` | int | |
| `entries` | `LogEntry[]` | All events for this run. |

### 4.6 `Settings`

A single object:

| Field | Type | Default | Notes |
|---|---|---|---|
| `logsEnabled` | bool | `false` | Setting is snapshotted at run start, so toggling it mid-run does not affect the in-progress run. |

---

## 5. Storage layout (Windows)

Use the user's roaming AppData folder. Layout:

```
%APPDATA%\TapScreenTap\
    scripts.json          # array of Script objects
    active_script.txt     # string: id of the currently-active script (absent = none)
    settings.json         # Settings object
    logs\
        <scriptId>.json   # ExecutionLog for that script (most recent only)
        index.json        # array of scriptIds with stored logs (for fast enumeration)
```

If using `shared_preferences_windows`, the equivalent keys are:

- `scripts_v1` — JSON string (array of Script).
- `active_script_id_v1` — string.
- `settings_logs_enabled` — bool.
- `execution_log_<scriptId>` — JSON string.
- `execution_log_index_v1` — JSON string (array of scriptIds).

The active-script selection MUST be cleared on every fresh process start (mirrors the Android `main()`'s `clearActiveScript()` call) so no row is preselected the next time the app launches.

Writes that update the same script's steps (e.g. from the recorder) MUST be serialized to avoid lost updates when two pieces of UI write simultaneously. A simple `Future`-chain or `Mutex` around the steps-update path is enough.

---

## 6. Coordinate system

### 6.1 Storage

All `TapStep.x` / `TapStep.y` values are stored as **physical pixels in virtual-desktop space** (the union of all monitor pixel rectangles, origin at the top-left of the virtual desktop). This is the same coordinate system used by `SendInput`'s `MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK` flag after conversion to the 0..65535 normalized range.

Reasons for physical-pixel storage:

- Lets the script execute correctly when the recorder window and the target window have different DPI scaling.
- Mirrors the Android implementation, allowing the same JSON to be exported/imported across platforms (subject to resolution differences).

### 6.2 Conversion to `SendInput`

`SendInput` with `MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK` expects coordinates normalized to `[0, 65535]` across the virtual screen:

```
normalizedX = (x - virtualLeft) * 65535 / (virtualWidth - 1)
normalizedY = (y - virtualTop)  * 65535 / (virtualHeight - 1)
```

Use `GetSystemMetrics(SM_XVIRTUALSCREEN / SM_YVIRTUALSCREEN / SM_CXVIRTUALSCREEN / SM_CYVIRTUALSCREEN)`. The app MUST be per-monitor DPI-aware (`SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)` or manifest entry) so `GetSystemMetrics` returns physical pixels.

### 6.3 Recorder ↔ stored coordinates

The recorder window is a borderless fullscreen window covering the whole virtual desktop. When the user taps at local position `(lx, ly)` within the recorder's client area:

```
stored.x = virtualLeft + lx_inPhysicalPx
stored.y = virtualTop  + ly_inPhysicalPx
```

The recorder runs DPI-aware so its client area is in physical pixels and no scaling is needed.

When loading existing steps for display, the reverse mapping is applied. If a script was recorded on a screen that no longer exists (e.g. the user disconnected the second monitor and one step lives at `x = 3500` when the current virtual desktop is `0..1920`), the marker is shown clipped to the recorder edge with a small "off-screen" badge; the underlying stored value is not mutated.

---

## 7. Permissions & first run

Windows does not require an accessibility permission for synthetic input from a user-mode process running at the same integrity level as the target app. The first-run flow is therefore lighter than Android's:

1. **Welcome screen** (only shown when no scripts file exists yet) with the app name, icon, and a brief description: "Automate clicks on Windows. Build a script, pick a point, tap Start."
2. A single "Get started" button takes the user to the main window.
3. The settings page exposes a single toggle: "Save execution logs" (off by default).

Optional UAC note (display when the app first detects the inability to send input to a foreground app): "If you want to click in apps running as Administrator, run Tap Screen Tap as Administrator too." Do not prompt for elevation automatically.

---

## 8. UI surfaces

The visual style mirrors Material 3 dark on Android. On Windows, prefer the Fluent dark theme (or the Flutter Material 3 dark theme if the existing UI is reused). Seed color stays purple: `#6C63FF`. Background near-black: `#131318`.

### 8.1 Main window

- Resizable, default size around 480×800 (mimics the phone aspect). Minimum 360×600.
- Title bar shows "Scripts" or "Logs" depending on the active tab.
- Top-right of the title bar: a "+" button (new script) and a gear button (settings).
- Bottom tab bar with two tabs:
  - **Scripts** (default).
  - **Logs**.
- The window cannot be closed while a script is running; clicking the close button minimizes to tray. A tray icon with right-click menu containing "Show", "Stop script", "Exit" is required.

#### 8.1.1 Scripts tab

A vertical list of cards, one per script. Each card contains:

- A **toggle switch** on the left — sets the active script. Only one script can be active at a time. Toggling on selects this script, toggling off (only the currently-active row can be toggled off) clears the selection.
- **Script name** (one line, ellipsized).
- A **subtitle** with: `N steps · Active · Last run <datetime>`. The `Active` segment is shown only when this row is active; the `Last run` segment is omitted when no run exists. Use the system short date+short time format.
- A **Delete** icon button → confirmation dialog ("Delete <name>? This cannot be undone.") with Cancel / Delete buttons. Deleting also removes the script's saved log.
- An **Edit** icon button → opens the script editor.

If no scripts exist: full-card empty state with "No scripts yet. Click + to create one."

A drop-down at the top of the list lets the user **import** a JSON file (`.tstscript`) or **export** the selected script. Both flows use the system file picker. The on-disk format is a single `Script` object (not wrapped in an array).

#### 8.1.2 Logs tab

Same card layout, one card per script (only scripts that have a stored log show up). Tapping a card opens the execution log screen for that script.

#### 8.1.3 Execution log screen

- Title: `<scriptName> log`.
- A summary card at the top:
  - Started: HH:mm:ss
  - Ended: HH:mm:ss (if present)
  - Duration: Ns (if present)
  - Stop reason: `<stopReason>`
  - Iterations: `completed / requested` (or just `completed` if requested = -1)
- Then a vertical list of entry cards, one per `LogEntry`, formatted by type:
  - `runStarted` — title "Run started", body "<stepCount> steps, iterations: <iterationsRequested>".
  - `iterationStarted` — title "Iteration <n>", body empty.
  - `tapPerformed` — title "Step <stepIndex+1> — Tap", body `Tapped (ax, ay)` or `Tapped (ax, ay) [jittered from (dx, dy), r=<radius>]` when `jitterApplied`.
  - `delayApplied` — title "Delay after step <n>" or "End delay" (when `stepIndex = -1`), body `Waited <total/1000>s (base <base>ms + random <random>ms)`.
  - `iterationCompleted` — title "Iteration <n> done", body empty.
  - `runEnded` — title "Run ended", body `<totalTaps> taps, <totalDurationMs>ms, <stopReason>`.
  - `error` — title "Error", body `<message>`.
- Each card shows the local time (HH:mm:ss) at the bottom.

If no log is recorded: empty state "No execution recorded yet".

#### 8.1.4 Script editor

A scrollable form with the following sections in order:

1. **Name** — single-line text field, label "Script name". Empty name on save shows an inline error.

2. **Global settings** header.

3. **Tap randomness** — switch tile. Subtitle: "Random point inside circle per tap".

4. **Global radius (px)** — number input. Hint text: "0 = disabled". Empty/0 = disabled. No upper limit.

5. **Default min delay (ms)** — slider 0..10000, divisions=100, label shows the current rounded value.

6. **Default max delay (ms)** — slider 0..15000, divisions=150.

7. **Global random delay** — switch tile. Subtitle: "Adds 0..max seconds to each wait".

8. **Max random delay (sec)** — slider 0..30, divisions=30.

9. **End delay (ms)** — slider 0..10000, divisions=100.

10. **Run mode** — segmented button with two segments: "Until stopped" / "Iterations". When "Iterations" is selected, a number input appears below: "Number of iterations", hint "e.g. 10", digits only, must be > 0. Switching from iterations back to until-stopped does **not** clear the typed count (re-selecting iterations restores it).

11. **Steps (N)** header.

12. If no steps: empty state text "No steps — use Record taps on the floating island".

13. Otherwise, a reorderable list (`ReorderableListView` equivalent), one tile per step:
   - Drag handle on the left.
   - "Step <i>: (x, y)" as the title.
   - Expand/collapse caret.
   - Delete icon.
   - When expanded: two text fields:
     - "Delay after (ms)" — number, hint "Empty = use default range".
     - "Radius override (px)" — number, hint "Empty = use global radius".

All editor changes are applied to the in-memory `_script` immediately; **only the explicit Save action persists**. The Save action is an icon button in the top-right of the editor's title bar. Show a small progress spinner where the icon would be while saving.

Save behavior:

- Trim the name; if empty, show a non-blocking error toast and do not save.
- After save, if `isNew` (the editor was opened via the "+" button), set this script as active and pop back to the main window.
- For existing scripts: show a "Script saved" toast; stay on the editor.

A subtle but important rule: when the user changes the steps in the recorder, the editor screen (if open) MUST refresh automatically without requiring a leave+return. Implement with a `Stream<void>` on a `scriptsChanged` broadcast bus that the editor subscribes to.

#### 8.1.5 Settings screen

Reached via the gear icon in the main window. Single section "App Settings" with one switch tile: "Save execution logs" / "Record tap-by-tap details for each script run. Disable to save storage and improve performance."

### 8.2 Control island

A small always-on-top, click-through-free, draggable window. Exact size: **300×150 logical pixels**. Rounded 12-px corners. Material elevation 4 equivalent (a soft drop shadow). Background: `surfaceContainerHigh` in dark mode (~`#1F1F23`).

Contents:

- Top line: the active script's name (one line, ellipsized). When no script is active, show "No active script" in muted color.
- A row of 3 icon buttons, equal width:
  1. **Start** — `play_arrow`. Filled style. Disabled when already running, or no active script, or active script has 0 steps.
  2. **Stop** — `stop`. Disabled unless a run is in progress.
  3. **Record** — `gps_fixed` (crosshair). Disabled while running, or when no active script.

Behavior:

- The island appears as soon as the main window opens, and stays even when the main window is minimized.
- The island is fully draggable (mouse-down on background → move). It snaps within the work area of the primary monitor.
- Position is remembered across sessions (`%APPDATA%\TapScreenTap\island.json` with `{x, y}`).
- Closing the main window minimizes to tray; the island stays visible.
- Right-click on the island opens a small popup menu: "Show main window", "Hide island", "Exit".

Window flags (Win32):

- `WS_POPUP`, no caption, no resize, no title bar.
- Extended style: `WS_EX_TOPMOST | WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE | WS_EX_LAYERED`.
- Use `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)` so the island does not appear in screen recordings — same intent as the Android click-through overlay being benign in captures.

While a script is running, the island MUST update its label/button states in real-time (the engine emits state changes on a Win32 message loop or via the platform channel).

### 8.3 Recorder overlay

A second always-on-top window that covers the **entire virtual desktop** (all monitors). It is opaque-ish (24% black tint) so the user can still see the underlying screen.

Layout:

- A single top-row bar pinned with safe padding from the edges (use 8 logical px from each side; on Windows there are no system insets to worry about).
- On the left of the bar: a black pill "Tap to add · Drag to move".
- On the right of the bar: a black pill containing 3 icon buttons in a row:
  - **Cancel** (×) — close the recorder without saving.
  - **Undo** — remove the most-recently-added marker. Disabled when there are no markers.
  - **Save** (✓) — persist the marker list to the script and close the recorder.

Interaction:

- Tapping (left mouse click) anywhere on the empty canvas adds a marker at that point. Markers are red circles (`#F87171ish` at 85% opacity) with a white centered numeric label (1-based, in insertion order).
- Each marker can be dragged with the mouse. The drag updates the stored physical coordinates using delta-based math (so the math is independent of the marker visual radius).
- Marker diameter is normally 36 logical px. If the step (or the script's global radius via `tapRandomnessEnabled`) defines a non-zero radius, the visual diameter is `(radius * 2) / DPI` logical px so the user sees the actual jitter circle.
- The "(N steps)" counter that exists in the Android pill must NOT be shown on Windows — there's a discoverability cost on desktop because users naturally read the title bar. Instead, show the count next to the script name in the control island (it already is shown there indirectly via the active-script-changed bus).
- Cancel discards all edits including new and existing markers (we do not partially save).
- Save persists, then closes the overlay and re-shows the control island.

Window flags:

- `WS_POPUP`, no caption.
- `WS_EX_TOPMOST | WS_EX_LAYERED`.
- Cover the entire virtual desktop: `GetSystemMetrics(SM_XVIRTUALSCREEN/SM_YVIRTUALSCREEN/SM_CXVIRTUALSCREEN/SM_CYVIRTUALSCREEN)`.
- `WS_EX_TRANSPARENT` is **not** set; the recorder must receive clicks.
- Make sure the recorder process is **per-monitor DPI-aware**, otherwise multi-monitor setups with different scaling will misplace markers.

### 8.4 Tray icon

A tray icon is required (Windows doesn't have a "background overlay service" pattern). The tray icon stays alive as long as the process. Right-click menu:

- **Show** — restores/focuses the main window.
- **Show island** / **Hide island** — toggles the island.
- **Start <activeScriptName>** — enabled only when a script is active and not running.
- **Stop** — enabled only when running.
- **Settings** — opens the settings screen.
- **Exit** — quits the app (confirmation dialog if a run is in progress).

Left-click on the tray icon toggles the main window.

---

## 9. Click engine (Win32)

This is the core of the port. The engine MUST be a single class running on a worker thread; the UI must not block.

### 9.1 Lifecycle

State machine:

- `Idle` → `Running` on `start(script, iterations)`.
- `Running` → `Idle` on `stop()` (user pressed Stop) — emits `runEnded { stopReason: "user_stopped" }`.
- `Running` → `Idle` after `iterations` completed when `runMode == iterations` — emits `runEnded { stopReason: "iterations_done" }`.
- `Running` → `Idle` on any gesture-dispatch failure — emits `error { message, stepIndex }` then `runEnded { stopReason: "error" }`.

A "gesture dispatch failure" on Windows corresponds to `SendInput` returning 0 (which is rare; usually means another process has the input desktop locked or UIPI prevented the synthesized event from reaching the target).

### 9.2 The run loop (pseudocode)

```
emit runStarted { scriptName, iterationsRequested, stepCount }

iterationsCompleted = 0
totalTaps = 0
stopReason = "user_stopped"
runStartMs = now()

try:
  while not cancelled:
    if iterationsRequested >= 0 and iterationsCompleted >= iterationsRequested:
      stopReason = "iterations_done"
      break

    emit iterationStarted { iteration: iterationsCompleted + 1 }

    for (index, step) in script.steps:
      if cancelled: break

      coords = resolveTapCoords(script, step)
      ok = dispatchTap(coords.x, coords.y)
      totalTaps += 1
      if ok: showRipple(coords.x, coords.y)  // §9.4

      emit tapPerformed {
        stepIndex: index,
        definedX: step.x, definedY: step.y,
        actualX: coords.x, actualY: coords.y,
        radiusPx: coords.radiusUsed,
        jitterApplied: coords.jitterApplied,
        gestureSuccess: ok,
      }

      if not ok:
        stopReason = "error"
        emit error { message: "SendInput failed", stepIndex: index }
        return

      // IMPORTANT: delay applies after every step including the last in the iteration
      delayInfo = computeDelay(script, step)
      if delayInfo.totalMs > 0:
        emit delayApplied { ...delayInfo, source }
        sleepInterruptible(delayInfo.totalMs)

    if cancelled: break

    if script.endDelayMs > 0:
      emit delayApplied { stepIndex: -1, baseDelayMs: endDelayMs, randomAddonMs: 0, totalDelayMs: endDelayMs, source: "endDelay" }
      sleepInterruptible(script.endDelayMs)

    iterationsCompleted += 1
    emit iterationCompleted { iteration: iterationsCompleted }

    if iterationsRequested >= 0 and iterationsCompleted >= iterationsRequested:
      stopReason = "iterations_done"
      break

finally:
  emit runEnded {
    totalTaps,
    totalDurationMs: now() - runStartMs,
    stopReason,
    iterationsCompleted,
    iterationsRequested,
  }
```

`sleepInterruptible` must be cancellable; the user pressing Stop wakes the thread immediately. Use a `WaitForSingleObject` on a stop event, or `std::condition_variable::wait_for`.

### 9.3 Delay computation

```
function computeDelay(script, step):
  if step.delayAfterMs != null:
    baseMs = step.delayAfterMs
    source = "perStep"
  else if script.defaultMinDelayMs >= script.defaultMaxDelayMs:
    baseMs = script.defaultMinDelayMs
    source = "defaultRange"
  else:
    baseMs = uniformInt(script.defaultMinDelayMs, script.defaultMaxDelayMs)  // inclusive on both ends
    source = "defaultRange"

  if script.globalRandomDelayEnabled and script.globalMaxRandomDelaySec > 0:
    randomAddonMs = uniformInt(0, script.globalMaxRandomDelaySec * 1000)
  else:
    randomAddonMs = 0

  return { baseMs, randomAddonMs, totalMs: baseMs + randomAddonMs, source }
```

Use a high-quality PRNG seeded from `std::random_device` per engine instance (no Math.random).

### 9.4 Tap coordinate resolution (jitter)

```
function resolveTapCoords(script, step):
  if not script.tapRandomnessEnabled:
    return { x: step.x, y: step.y, jitterApplied: false, radiusUsed: 0 }

  radius = step.radiusPx ?? script.globalRadiusPx
  if radius <= 0:
    return { x: step.x, y: step.y, jitterApplied: false, radiusUsed: 0 }

  // Uniform sample in a disc:
  u = uniformReal(0, 1)
  v = uniformReal(0, 1)
  r = radius * sqrt(u)
  theta = 2 * PI * v
  dx = r * cos(theta)
  dy = r * sin(theta)
  return { x: step.x + dx, y: step.y + dy, jitterApplied: true, radiusUsed: radius }
```

The `sqrt(u)` is required for uniform-area sampling; do not replace it with `u`.

### 9.5 Dispatching the tap

Use `SendInput` with two events: a `MOUSEEVENTF_LEFTDOWN` followed by a `MOUSEEVENTF_LEFTUP`. There must be a **non-zero gap** between the two — synthesize at least 30 ms of pause, matching the Android `TAP_DURATION_MS = 50` (use 50 ms for parity). Some games and many controls reject zero-duration clicks.

Implementation:

```cpp
INPUT inputs[2] = {};
inputs[0].type = INPUT_MOUSE;
inputs[0].mi.dx = normalizedX;
inputs[0].mi.dy = normalizedY;
inputs[0].mi.dwFlags = MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK | MOUSEEVENTF_MOVE | MOUSEEVENTF_LEFTDOWN;

// First, fire down only.
auto sent = SendInput(1, &inputs[0], sizeof(INPUT));
if (sent != 1) return false;

Sleep(50);  // tap duration

inputs[1].type = INPUT_MOUSE;
inputs[1].mi.dx = normalizedX;
inputs[1].mi.dy = normalizedY;
inputs[1].mi.dwFlags = MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK | MOUSEEVENTF_LEFTUP;
return SendInput(1, &inputs[1], sizeof(INPUT)) == 1;
```

Notes:

- The mouse cursor is moved to the tap location as part of the tap. This is intentional and matches the Android behavior (which only synthesizes a touch — but on desktop, moving the cursor is the only way to get an absolute click into the foreground window).
- The mouse cursor restoration is **not** required (the user expects the cursor to end up where the script ran). If a "restore cursor position" setting is added later, save the cursor pos via `GetCursorPos` before each tap and restore via `SetCursorPos` after `MOUSEEVENTF_LEFTUP`.
- `SendInput` calls into the same input queue as the keyboard/mouse driver; events arrive after a single `GetMessage` cycle in the target window. No additional delay between events is needed beyond the 50 ms tap duration.

### 9.6 Ripple effect

Optional but recommended (matches Android `TapRippleOverlay`): when a tap fires successfully, show a fading ring at the tap location for ~200 ms. Implement as a layered topmost click-through window (`WS_EX_TOPMOST | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE`) auto-destroyed when the animation ends. Max radius 30 px, stroke 2 px, color white at 80% opacity, animate radius 8→30 and alpha 1→0 linearly.

`WS_EX_TRANSPARENT` is essential — the ripple must NOT intercept the synthetic click that just fired (race: the click and the ripple happen back-to-back, but the click already left the queue before the ripple window appears, so this is mostly a belt-and-braces measure).

### 9.7 Events / state propagation

Expose two channels (in Flutter terms; otherwise an event bus):

- `MethodChannel`-equivalent: `start(script, iterations)`, `stop()`, `isRunning()`, `openSettings()`, `getDisplayMetrics()`.
- `EventChannel`-equivalent: streams `clickingStateChanged { isClicking }`, `iterationCompleted { iteration }`, `logEvent { scriptId, entry }`, `recorderDone`.

Channel names (if reusing Flutter): `com.tap_screen_tap/clicker` and `com.tap_screen_tap/clicker_events`. Keep the schemas identical to Android for parity.

---

## 10. Cross-cutting behaviors

### 10.1 Active script management

- Only one script may be active at a time.
- Activating a script writes its ID to `active_script.txt` (or the equivalent pref).
- Deactivating the currently-active script clears the file.
- Deleting the active script also clears the file.
- The island reflects the active script in real-time (it subscribes to a broadcast bus).
- While a run is in progress, the scripts list MUST keep the running script highlighted even if some race transiently clears the active-script storage; track the "running script id" in memory separately from the persisted active-script id, and prefer the in-memory value for display.

### 10.2 First launch invariants

On every process start:
- Clear `active_script.txt` so no row is preselected.
- Show the welcome screen if `scripts.json` does not exist; otherwise jump straight to the main window.
- Spawn the control island after the main window is ready (post-first-frame).

### 10.3 Refresh after recorder save

When the recorder saves, three things MUST update without user action:

1. The script editor screen (if open) refreshes its step list.
2. The Scripts tab refreshes its `N steps` and `Last run` subtitles.
3. The island re-reads the active script so its enabled state reflects the new step count.

All three subscribe to a single broadcast: emit `scriptsChanged` on save.

### 10.4 Window-hide hygiene during runs

If the main window is open while a script runs, the runtime cost of redraws can introduce small but visible delays in the input loop. The engine MUST run on a dedicated thread, never on the UI thread.

### 10.5 Cancellation latency

User pressing Stop must terminate the run within 200 ms. The `sleepInterruptible` mechanism makes this trivial as long as the longest non-interrupted operation is the single 50-ms tap dispatch.

### 10.6 Logging snapshot

The "logsEnabled" setting is read **once** at `runStarted` time and cached for the entire run. Toggling the setting mid-run does not affect the run already in progress, but DOES affect the next run.

### 10.7 Multi-monitor

Recording on monitor A, running on monitor B: works as long as both monitors are still attached. If the monitor the script was recorded on is later disconnected and the coordinates fall outside the current virtual desktop, the engine still dispatches them (Windows clips internally). Log a one-time warning (an `error` log entry of severity warning) but do not abort the run.

DPI scaling differs per monitor: store everything in physical pixels (§6); never store logical/scaled coordinates.

---

## 11. Win32 surface (cheat sheet)

| Concern | API |
|---|---|
| Synthesize input | `SendInput` with `INPUT_MOUSE`, `MOUSEEVENTF_VIRTUALDESK` |
| Get monitor layout | `EnumDisplayMonitors`, `GetMonitorInfo` |
| Virtual desktop bounds | `GetSystemMetrics(SM_X/Y/CX/CYVIRTUALSCREEN)` |
| DPI awareness | `SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)` or manifest |
| Always-on-top | `WS_EX_TOPMOST` |
| Borderless | `WS_POPUP`, omit `WS_CAPTION`/`WS_SYSMENU` |
| Click-through | `WS_EX_TRANSPARENT` (use only for the ripple) |
| Layered/alpha | `WS_EX_LAYERED`, `SetLayeredWindowAttributes` |
| Hide from captures | `SetWindowDisplayAffinity(WDA_EXCLUDEFROMCAPTURE)` |
| Tray icon | `Shell_NotifyIcon` |
| Hotkeys (optional) | `RegisterHotKey` |
| AppData path | `SHGetKnownFolderPath(FOLDERID_RoamingAppData)` |

UIPI / Integrity:

- A medium-integrity (normal) process cannot send input into windows of higher-integrity processes (typically apps running as Administrator). If the user's target needs this, the app must run elevated.
- Apps that need to bypass UIPI legitimately can ship with an `uiAccess="true"` manifest, but this requires the binary to be signed with a UIAccess-capable certificate and installed under `Program Files`. Most users won't want this.

---

## 12. Edge cases & known pitfalls

- **Tap on an inactive window**: `SendInput` activates the window under the cursor as a side effect of the move+click sequence. This is desirable (it matches what a human would do).
- **Tap into a fullscreen exclusive game**: works in most cases; some anti-cheats block it. Out of scope.
- **`Sleep(50)` between down and up**: do NOT use `WaitForSingleObject` here — keep it a pure `Sleep` so the tap rhythm is consistent.
- **High-DPI**: ensure the manifest has `<dpiAwareness>PerMonitorV2</dpiAwareness>` AND the recorder and control windows are also DPI-aware. A mismatch makes markers appear in the wrong place.
- **Different virtual-desktop topology between record-time and run-time**: store physical absolute coordinates, do not rebase to monitor-relative.
- **Two scripts with same name**: allowed; IDs disambiguate.
- **Iteration count 0**: prevent in UI (must be `>= 1`); engine should still gracefully bail with `runEnded { iterationsCompleted: 0, stopReason: "iterations_done" }`.
- **Zero-step script**: Start button is disabled; if somehow invoked, engine emits `runStarted` → `runEnded` immediately with `stopReason: "iterations_done"` and `totalTaps: 0`.
- **Concurrent step writes from editor + recorder**: serialize through the same write chain (the existing `_writeChain` pattern from `script_repository.dart` is the right approach).
- **App killed mid-run**: no special cleanup needed; the next start re-reads everything from disk. The previous `ExecutionLog` is left in its in-progress state (`endedAt = null`, `stopReason = "running"`) which the Logs screen renders as "Last run: <startedAt>" — acceptable.

---

## 13. Out-of-scope (deliberately)

- Recording mouse movements / drags / right-clicks — taps only.
- Keyboard input synthesis.
- Image-matching triggers ("tap when this pixel is red").
- Scheduled runs.
- Cloud sync of scripts.
- Multi-user / per-user profiles.

These are nice-to-have backlog items, not v1 requirements.

---

## 14. Acceptance checklist

A finished Windows build passes when **all** of these are true:

- [ ] Fresh install: no welcome friction. App opens, main window shows empty state, island appears bottom-right of the primary monitor's work area.
- [ ] Creating a script via "+" opens the editor with default values; saving makes it active and returns to the scripts list.
- [ ] Recording: clicking the island's record button opens a fullscreen tinted overlay covering all monitors; tapping creates a numbered marker; dragging moves it; Undo removes the last; Cancel discards; Save persists and returns to the island.
- [ ] The script editor live-updates the step count and step list when recorder saves.
- [ ] Starting a script clicks at the exact recorded points; with `tapRandomnessEnabled` and a non-zero radius, taps fall inside the disc; the Stop button halts within 200 ms.
- [ ] Logging off: no JSON is written under `logs\`. Logging on: each run replaces the previous log for that script and renders in the Logs tab.
- [ ] Closing the main window minimizes to tray; tray menu can stop a running script and exit the app.
- [ ] Multi-monitor with different DPI: marker placement matches click location for both the same monitor and a cross-monitor recording.
- [ ] Active-script selection is cleared on every fresh app launch.
- [ ] The Iterations run mode stops exactly after N iterations and the log reads `iterations_done`.
- [ ] Global random delay adds at most `globalMaxRandomDelaySec * 1000` ms on top of per-step delays.
