# Tap Screen Tap — macOS Specification

A complete behavioral and UI specification for porting the existing Android "Tap Screen Tap" auto-tapper to macOS. This document is exhaustive on purpose: feed it whole to an AI agent or a developer and they should be able to build the app without referring back to the Android codebase.

---

## 1. Product overview

Tap Screen Tap is a desktop auto-tapper. The user defines **scripts**, each a list of ordered **tap steps** plus a small set of timing/randomness settings. The user picks one active script, opens a small always-on-top **control island**, and starts/stops execution from there. Taps are dispatched as synthetic mouse clicks targeting absolute screen coordinates, even when the user has other applications focused.

Two foreground surfaces exist while the app is running:

1. **Main window** — script management, logs, settings.
2. **Floating control island** — small, draggable, always-on-top window with Start / Stop / Record buttons and the active script's name.

A third transient surface appears while recording:

3. **Fullscreen recorder overlay** — covers the entire display(s), lets the user tap to add markers, drag to move them, undo, save, cancel.

The original Android version runs taps via the AccessibilityService and dispatches `GestureDescription`s. The macOS version dispatches taps via `CGEvent` / `CGEventPost` with absolute screen coordinates, after the user has granted **Accessibility** permission (and **Screen Recording** permission for marker placement to behave correctly with multi-display setups under privacy-restricted screen captures).

---

## 2. Recommended tech stack

The reference implementation is Flutter (Dart) for the cross-platform UI plus Kotlin for native Android. For macOS, the recommended choices are:

| Layer | Primary recommendation | Alternative |
|---|---|---|
| UI framework | **Flutter for macOS** (so the same Dart UI code can be reused; only the platform channel changes) | SwiftUI / Catalyst |
| Native plugin | Swift via the Flutter macOS plugin template | Objective-C, or pure Swift app |
| Persistence | `shared_preferences_foundation` (writes to `NSUserDefaults`) | A JSON file in Application Support |
| Build/distribution | App Store **or** notarized DMG/PKG with a Developer ID cert | unsigned (only for personal use) |
| Min macOS | macOS 12 Monterey | macOS 11 if you accept the lack of certain APIs (e.g. `CGRequestScreenCaptureAccess` was added in 10.15 so it's fine either way) |

Reuse from the Flutter codebase is direct: the Dart UI, models, repositories, the script editor, the logs screen, and the click "controller" logic can all be reused with a different platform channel implementation. Replace the Android-specific bits (accessibility service, overlay window, gesture dispatch) with the macOS equivalents described below.

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
| `x` | number (double) | yes | Absolute screen X coordinate in the **global display coordinate space** (see §6.1). |
| `y` | number (double) | yes | Absolute screen Y coordinate in the **global display coordinate space** (see §6.1). |
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

## 5. Storage layout (macOS)

Use the user's Application Support folder. Layout:

```
~/Library/Application Support/TapScreenTap/
    scripts.json          # array of Script objects
    active_script.txt     # string: id of the currently-active script (absent = none)
    settings.json         # Settings object
    logs/
        <scriptId>.json   # ExecutionLog for that script (most recent only)
        index.json        # array of scriptIds with stored logs (for fast enumeration)
```

If using `shared_preferences_foundation`, the equivalent NSUserDefaults keys are:

- `scripts_v1` — JSON string (array of Script).
- `active_script_id_v1` — string.
- `settings_logs_enabled` — bool.
- `execution_log_<scriptId>` — JSON string.
- `execution_log_index_v1` — JSON string (array of scriptIds).

The active-script selection MUST be cleared on every fresh process start (mirrors the Android `main()`'s `clearActiveScript()` call) so no row is preselected the next time the app launches.

Writes that update the same script's steps (e.g. from the recorder) MUST be serialized to avoid lost updates when two pieces of UI write simultaneously. A simple `Future`-chain or serial `DispatchQueue` around the steps-update path is enough.

**Sandboxing:** if you target the App Store, the app must run sandboxed. The Accessibility-driven event posting **does** work in a sandboxed app but the sandbox does NOT grant Accessibility automatically — the user must still allow it under System Settings. The sandbox entitlements you need are `com.apple.security.app-sandbox = true`, `com.apple.security.files.user-selected.read-write = true` (for import/export), and a `com.apple.security.temporary-exception.apple-events` entry for the Accessibility check. If you ship outside the store (Developer ID notarized), you can drop the sandbox and rely solely on hardened-runtime + notarization.

---

## 6. Coordinate system

### 6.1 Storage

All `TapStep.x` / `TapStep.y` values are stored in **global display coordinate space**, in points (Cocoa's coordinate unit), with the origin at the **top-left** of the primary display (Cocoa's natural origin is bottom-left, but the app stores top-left for parity with Android and Windows — see §6.2 for conversions).

When multiple displays are connected, this is the union of all display rectangles using the **Quartz Display Services** convention: y grows downward, all displays share one coordinate space, origin at top-left of the leftmost top-most display arrangement.

Reasons for point-not-pixel storage:

- macOS's `CGEvent` APIs accept points, not physical pixels. Retina displays use a 2× backing scale but `CGEvent` still expects points (the OS scales internally).
- The recorder and the engine therefore use the same units. No DPI math is required at dispatch time.

### 6.2 Cocoa vs Quartz coordinate flip

- Cocoa/AppKit uses **bottom-left origin**, Y growing upward.
- Quartz Display Services / Core Graphics / `CGEvent` uses **top-left origin**, Y growing downward.

The app stores **top-left, Y-down** values (the Quartz convention) because `CGEventCreateMouseEvent` takes them directly. When you need to place a marker visually in a Cocoa view, flip using the screen height:

```swift
// stored.y is top-left/Y-down (Quartz)
let cocoaY = NSScreen.screens.maxY - stored.y
```

Where `NSScreen.screens.maxY` is the bottom of the lowest display in NSScreen-arrangement terms. Encapsulate this in a single helper and use it everywhere — do NOT inline the flip.

### 6.3 Recorder ↔ stored coordinates

The recorder window is a borderless fullscreen window covering all displays. When the user taps at local position `(lx, ly)` in the recorder window's content view (which is in Cocoa coordinates by default):

1. Convert the click to window coordinates with `event.locationInWindow`.
2. Convert window → screen via `window.convertToScreen(rect:)`.
3. Convert Cocoa-screen → Quartz-screen via the flip in §6.2.
4. Store that as `(x, y)`.

For displaying existing markers, do the reverse. Make sure the recorder is configured for **per-display DPI** (the default for borderless windows on Cocoa).

### 6.4 Multiple displays

`NSScreen.screens` gives you every active display. The "global Quartz space" is the union of their frames after the flip. If a script's coordinates fall outside the current union (the user disconnected a display since recording), draw the marker clamped to the union edge with a "off-screen" badge; never mutate the stored value.

---

## 7. Permissions & first run

macOS requires explicit user grants for two things:

1. **Accessibility** — required to post synthetic mouse events into other apps.
2. **Screen Recording** — *not* required for `CGEventPost` itself, but **required** for `CGDisplayCreateImage` and (more importantly for us) for `CGWindowListCreateImage` calls; we don't actually need to record the screen, but on macOS Sequoia (15) and later, posting mouse events into another window via Accessibility may surface a one-time prompt referencing "screen capture". Treat it as best-effort: if denied, taps still work; some captures used for the optional ripple may fail and the ripple is simply skipped.

First-run flow:

1. **Welcome screen** with the app name, icon, and a brief description.
2. A "Permissions" page with two cards:
   - **Accessibility** — title, subtitle "Required to send taps to other apps". Button "Open System Settings" opens the Accessibility pane preselected (see §11 for the URL). A green check appears when the app detects the permission.
   - **Screen Recording (optional)** — title, subtitle "Enables tap ripples and on-screen previews". Button "Open System Settings".
3. A "Continue" button is enabled once Accessibility is granted. Screen Recording is optional.
4. After continue, the user lands on the main window and the control island spawns.

The permissions screen is reachable later via Settings → "Permissions".

Important: macOS does NOT auto-restart your app when you toggle Accessibility — it does, however, kill the helper process providing accessibility (which is your app), so it's good practice to poll the permission with `AXIsProcessTrustedWithOptions` every 1.5 seconds while the permissions screen is open, and to check it once on every `applicationDidBecomeActive`.

---

## 8. UI surfaces

The visual style mirrors Material 3 dark on Android. On macOS, you may stay with Material 3 (Flutter), or use the system dark appearance with Cocoa controls; either is fine. Seed color stays purple: `#6C63FF`. Background near-black: `#131318`.

### 8.1 Main window

- Standard macOS window: title bar, traffic lights, resizable, default size around 480×800 (mimics the phone aspect). Minimum 360×600.
- Title bar shows "Scripts" or "Logs" depending on the active tab. The title bar is **not** transparent.
- Top-right of the title bar: a "+" toolbar item (new script) and a gear toolbar item (settings).
- Inside the content area, a segmented control or tab bar with two segments:
  - **Scripts** (default).
  - **Logs**.

Window-close behavior:

- The red traffic light hides the window (sets `isVisible = false`). It does NOT terminate the app.
- The app keeps running with the island and tray (status-bar) item visible. Quit only via Cmd-Q, the app menu's "Quit", or the status-bar menu.
- If a script is running, the close gesture still hides the window; the status-bar item is the only place the run can be stopped while the window is hidden.
- `applicationShouldTerminateAfterLastWindowClosed` returns `false`.

#### 8.1.1 Scripts tab

A vertical list of cards, one per script. Each card contains:

- A **toggle switch** on the left — sets the active script. Only one script can be active at a time. Toggling on selects this script, toggling off (only the currently-active row can be toggled off) clears the selection.
- **Script name** (one line, ellipsized).
- A **subtitle** with: `N steps · Active · Last run <datetime>`. The `Active` segment is shown only when this row is active; the `Last run` segment is omitted when no run exists. Use a localized date+time format.
- A **Delete** icon button (trash) → confirmation dialog ("Delete <name>? This cannot be undone.") with Cancel / Delete buttons. Deleting also removes the script's saved log.
- An **Edit** icon button (pencil) → opens the script editor.

If no scripts exist: full-card empty state with "No scripts yet. Click + to create one."

A toolbar menu lets the user **import** a JSON file (`.tstscript` UTI) or **export** the selected script. The on-disk format is a single `Script` object.

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

10. **Run mode** — segmented button with two segments: "Until stopped" / "Iterations". When "Iterations" is selected, a number input appears below: "Number of iterations", hint "e.g. 10", digits only, must be > 0. Switching from iterations back to until-stopped does **not** clear the typed count.

11. **Steps (N)** header.

12. If no steps: empty state text "No steps — use Record taps on the floating island".

13. Otherwise, a reorderable list, one tile per step:
   - Drag handle on the left (NSTableView with row reordering, or a Flutter `ReorderableListView`).
   - "Step <i>: (x, y)" as the title.
   - Expand/collapse caret.
   - Delete icon.
   - When expanded: two text fields:
     - "Delay after (ms)" — number, hint "Empty = use default range".
     - "Radius override (px)" — number, hint "Empty = use global radius".

All editor changes are applied to the in-memory `_script` immediately; **only the explicit Save action persists**. The Save action is an icon button (save / disk icon) in the top-right of the editor's toolbar. Show a small progress spinner where the icon would be while saving.

Save behavior:

- Trim the name; if empty, show a non-blocking error toast and do not save.
- After save, if `isNew`, set this script as active and pop back to the main window.
- For existing scripts: show a "Script saved" toast; stay on the editor.

A subtle but important rule: when the user changes the steps in the recorder, the editor screen (if open) MUST refresh automatically without requiring a leave+return. Implement with a notification on a `NotificationCenter` named `.tstScriptsChanged`, or an equivalent broadcast on whichever stack you use.

#### 8.1.5 Settings screen

Reached via the gear toolbar item. Sections:

- **Permissions** — same two cards as on the welcome screen, reachable here too.
- **App Settings** — single switch tile: "Save execution logs" / "Record tap-by-tap details for each script run. Disable to save storage and improve performance."

### 8.2 Control island

A small always-on-top, click-through-free, draggable window. Exact size: **300×150 points**. Rounded 12-pt corners. Subtle shadow. Background: `surfaceContainerHigh` in dark mode (~`#1F1F23`).

Contents:

- Top line: the active script's name (one line, ellipsized). When no script is active, show "No active script" in muted color.
- A row of 3 icon buttons, equal width:
  1. **Start** — `play.fill` SF Symbol. Filled style. Disabled when already running, or no active script, or active script has 0 steps.
  2. **Stop** — `stop.fill`. Disabled unless a run is in progress.
  3. **Record** — `dot.viewfinder` (crosshair). Disabled while running, or when no active script.

Behavior:

- The island appears as soon as the main window opens, and stays even when the main window is hidden.
- The island is fully draggable (mouse-down on background → move). It snaps to within the visibleFrame of the screen it currently lives on.
- Position is remembered across sessions (NSUserDefaults `island_position` = `"x,y"`).
- Closing/hiding the main window does not affect the island.
- Right-click on the island opens an NSMenu: "Show main window", "Hide island", "Quit".

Window flags (AppKit):

- `NSPanel` subclass, `styleMask = [.borderless, .nonactivatingPanel]`.
- `level = NSWindow.Level.statusBar` (above normal windows, below modal sheets — works for an always-on-top island).
- `collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]` so the island appears on every space and over fullscreen apps.
- `isMovable = true`, but suppress automatic dragging: use a custom mousedown→drag handler so dragging works only when the user grabs the background, not when clicking a button.
- `backgroundColor = .clear`, content view has a CALayer with rounded corners and shadow.
- `sharingType = .none` so the island is not captured by screen recordings (the macOS equivalent of Android's "click-through overlay").

While a script is running, the island MUST update its label/button states in real-time (the engine emits state changes through a Combine publisher or via the platform channel).

### 8.3 Recorder overlay

A second always-on-top window that covers the **union of all displays**. It is opaque-ish (24% black tint) so the user can still see the underlying screen.

Layout:

- A single top-row bar pinned with safe padding from the edges (use 8 pt from each side, plus respect `safeAreaInsets.top` on displays with notches like the MBP).
- On the left of the bar: a black pill "Tap to add · Drag to move".
- On the right of the bar: a black pill containing 3 icon buttons in a row:
  - **Cancel** (×) — close the recorder without saving.
  - **Undo** — remove the most-recently-added marker. Disabled when there are no markers.
  - **Save** (✓) — persist the marker list to the script and close the recorder.

Interaction:

- Tapping (left mouse click) anywhere on the empty canvas adds a marker at that point. Markers are red circles (system red at 85% opacity) with a white centered numeric label (1-based).
- Each marker can be dragged with the mouse. The drag updates the stored coordinates using delta-based math.
- Marker diameter is normally 36 pt. If the step (or the script's global radius via `tapRandomnessEnabled`) defines a non-zero radius, the visual diameter is `radius * 2` pt so the user sees the actual jitter circle.
- Cancel discards all edits including new and existing markers (we do not partially save).
- Save persists, then closes the overlay and re-shows the control island.

Window flags:

- `NSPanel`, `styleMask = [.borderless, .nonactivatingPanel]`.
- `level = NSWindow.Level.screenSaver` so the recorder is above the dock and notification banners.
- `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`.
- `frame = NSScreen.screens.reduce(.zero) { $0.union($1.frame) }` — the union of all screens in Cocoa space. Recompute on `NSApplication.didChangeScreenParametersNotification`.
- `ignoresMouseEvents = false` — the recorder must receive clicks.
- `acceptsFirstMouse = true` so the first click after the recorder appears is registered as a marker placement (not consumed by focus-following).

### 8.4 Status-bar item (menu bar)

A status-bar item (NSStatusItem with `length = NSStatusItem.variableLength`) is required (macOS doesn't have a "tray", but the menu bar serves the same purpose). The status-bar item stays alive as long as the process. Right-click (or left-click — they should be the same) menu:

- **Show** — `NSApp.activate(ignoringOtherApps: true)` + show the main window.
- **Show island** / **Hide island** — toggles the island.
- **Start <activeScriptName>** — enabled only when a script is active and not running.
- **Stop** — enabled only when running.
- **Settings** — opens the settings screen.
- **Quit** — terminates the app (confirmation dialog if a run is in progress).

The icon: a small SF Symbol `cursorarrow.click` (template image so it adapts to light/dark menu bar).

---

## 9. Click engine (CGEvent / Accessibility)

This is the core of the port. The engine MUST be a single class running on a worker queue; the UI must not block.

### 9.1 Lifecycle

State machine:

- `Idle` → `Running` on `start(script, iterations)`.
- `Running` → `Idle` on `stop()` (user pressed Stop) — emits `runEnded { stopReason: "user_stopped" }`.
- `Running` → `Idle` after `iterations` completed when `runMode == iterations` — emits `runEnded { stopReason: "iterations_done" }`.
- `Running` → `Idle` on any gesture-dispatch failure — emits `error { message, stepIndex }` then `runEnded { stopReason: "error" }`.

A "gesture dispatch failure" on macOS corresponds to `CGEventPost` returning into a state where the Accessibility permission was revoked mid-run, or when the event tap is denied. The first failure aborts.

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
        emit error { message: "CGEvent dispatch failed", stepIndex: index }
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

`sleepInterruptible` must be cancellable; the user pressing Stop wakes the thread immediately. Use a `DispatchSemaphore.wait(timeout:)` or `Task.sleep` inside a Swift `Task` that is cancelled on stop.

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

Use `SystemRandomNumberGenerator` (Swift) which is cryptographically-seeded — no need for explicit seeding.

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

Use Quartz Event Services. Synthesize a left mouse down, sleep ~50 ms, then a left mouse up at the same location. 50 ms matches the Android `TAP_DURATION_MS` for cross-platform parity and is required for most apps to register the click as a real click (rather than a press-then-cancel).

```swift
func dispatchTap(at point: CGPoint) -> Bool {
    let source = CGEventSource(stateID: .combinedSessionState)

    guard
        let mouseDown = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseDown,
            mouseCursorPosition: point,
            mouseButton: .left
        ),
        let mouseUp = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseUp,
            mouseCursorPosition: point,
            mouseButton: .left
        )
    else { return false }

    mouseDown.post(tap: .cghidEventTap)
    // Tap duration — keeps parity with the Android engine (50 ms).
    Thread.sleep(forTimeInterval: 0.050)
    mouseUp.post(tap: .cghidEventTap)
    return true
}
```

Notes:

- `point` is in Quartz coordinates (top-left origin, Y-down). The stored coordinates are already in this space.
- `CGEventSource(stateID: .combinedSessionState)` blends in the real user's modifier state. Use `.privateState` if you want the synthetic event to ignore physical modifiers.
- The mouse cursor is moved to the tap location as part of the event. This is intentional and matches the Android behavior.
- If `CGEventPost` is denied (Accessibility revoked at runtime), the function returns true at the call level but the event is dropped silently. There's no reliable post-hoc check; instead, gate on `AXIsProcessTrustedWithOptions` at run start and emit `error` if it returns false.

Pre-flight check (at the very start of `runScript`):

```swift
let opts = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: false] as CFDictionary
guard AXIsProcessTrustedWithOptions(opts) else {
    emit error { message: "Accessibility permission not granted" }
    return
}
```

Do NOT pass `prompt: true` here; the engine should run silently. The permissions screen is the only place that prompts.

### 9.6 Ripple effect

Optional but recommended (matches Android `TapRippleOverlay`): when a tap fires successfully, show a fading ring at the tap location for ~200 ms. Implement as a borderless click-through `NSWindow`:

- `styleMask = .borderless`
- `level = .screenSaver`
- `ignoresMouseEvents = true` (this is the click-through bit)
- `acceptsMouseMovedEvents = false`
- `isOpaque = false`, `backgroundColor = .clear`
- Auto-destroyed when the animation ends.

Max radius 30 pt, stroke 2 pt, color white at 80% opacity, animate radius 8→30 and alpha 1→0 linearly.

### 9.7 Events / state propagation

Expose two channels (in Flutter terms; otherwise a Combine publisher):

- `MethodChannel`-equivalent: `start(script, iterations)`, `stop()`, `isRunning()`, `getDisplayMetrics()`, `isAccessibilityEnabled()`, `openAccessibilitySettings()`.
- `EventChannel`-equivalent: streams `clickingStateChanged { isClicking }`, `iterationCompleted { iteration }`, `logEvent { scriptId, entry }`, `recorderDone`.

Channel names (if reusing Flutter): `com.tap_screen_tap/clicker` and `com.tap_screen_tap/clicker_events`. Keep the schemas identical to Android for parity.

---

## 10. Cross-cutting behaviors

### 10.1 Active script management

- Only one script may be active at a time.
- Activating a script writes its ID to `active_script.txt` (or the equivalent default).
- Deactivating the currently-active script clears the file.
- Deleting the active script also clears the file.
- The island reflects the active script in real-time (it subscribes to a broadcast bus).
- While a run is in progress, the scripts list MUST keep the running script highlighted even if some race transiently clears the active-script storage; track the "running script id" in memory separately and prefer it for display.

### 10.2 First launch invariants

On every process start:
- Clear `active_script.txt` so no row is preselected.
- Show the welcome+permissions screen if Accessibility is not yet granted; otherwise jump straight to the main window.
- Spawn the control island after the main window is ready.

### 10.3 Refresh after recorder save

When the recorder saves, three things MUST update without user action:

1. The script editor screen (if open) refreshes its step list.
2. The Scripts tab refreshes its `N steps` and `Last run` subtitles.
3. The island re-reads the active script so its enabled state reflects the new step count.

All three subscribe to a single broadcast: post `scriptsChanged` on save.

### 10.4 Window-hide hygiene during runs

If the main window is open while a script runs, the runtime cost of redraws can introduce small but visible delays in the input loop. The engine MUST run on a dedicated `DispatchQueue` (or detached `Task`), never on the main thread.

### 10.5 Cancellation latency

User pressing Stop must terminate the run within 200 ms. The `sleepInterruptible` mechanism makes this trivial as long as the longest non-interrupted operation is the single 50-ms tap dispatch.

### 10.6 Logging snapshot

The "logsEnabled" setting is read **once** at `runStarted` time and cached for the entire run. Toggling the setting mid-run does not affect the in-progress run, but DOES affect the next run.

### 10.7 Multi-display & Spaces

- Recording on display A, running on display B: works as long as both displays are still attached.
- Switching macOS Spaces (via Mission Control) does not stop the run — the engine runs in the background regardless.
- `applicationDidChangeOcclusionState`: not relevant; the run continues.
- macOS Stage Manager: the island appears in every stage (it has `.canJoinAllSpaces`).

### 10.8 Sleep / lid close

- Mac going to sleep mid-run: the engine sees the dispatch queue suspended; on wake, the run resumes from where it was. This is acceptable.
- Display sleep (but Mac awake): no effect; events still post.

---

## 11. Cocoa / Quartz surface (cheat sheet)

| Concern | API |
|---|---|
| Synthesize input | `CGEvent(mouseEventSource:mouseType:mouseCursorPosition:mouseButton:)` + `.post(tap: .cghidEventTap)` |
| Check Accessibility | `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: false])` |
| Open Accessibility prefs | `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)` |
| Open Screen-Recording prefs | `NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)` |
| Get displays | `NSScreen.screens` (Cocoa) or `CGGetActiveDisplayList` (Quartz) |
| Global screen bounds | union of `NSScreen.screens.map { $0.frame }` |
| Always-on-top | `NSPanel` with `level = .statusBar` or `.screenSaver` |
| Borderless | `styleMask = [.borderless, .nonactivatingPanel]` |
| Click-through | `ignoresMouseEvents = true` |
| Hide from captures | `window.sharingType = .none` |
| Status-bar item | `NSStatusBar.system.statusItem(withLength:)` |
| Hotkeys (optional) | `Carbon RegisterEventHotKey` or `MASShortcut` |
| Application Support path | `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)` |
| Hardened runtime entitlements | `com.apple.security.cs.allow-unsigned-executable-memory` may be needed for Flutter; `com.apple.security.automation.apple-events` if you ever script other apps |

Sandbox entitlements (if App Store):

- `com.apple.security.app-sandbox = true`
- `com.apple.security.files.user-selected.read-write = true`
- Note: sandboxed apps STILL require the user to grant Accessibility manually; the sandbox doesn't bypass that.

---

## 12. Edge cases & known pitfalls

- **Tap on an inactive app**: `CGEventPost` does NOT bring the target window forward; it sends the click to whatever window is at that location. This matches Android-tap behavior and is desirable.
- **Tap into a fullscreen app**: works in nearly all cases.
- **Tap into another macOS app needing Accessibility**: the tap is delivered; the other app doesn't see the difference between user and synthetic input (unless it specifically checks `CGEventGetIntegerValueField(.eventSourceUserData)`).
- **High-DPI / Retina**: `CGEvent` takes points, not backing pixels. No DPI math at dispatch.
- **Multiple displays with different scales**: each display has its own `backingScaleFactor`; CGEvent abstracts it away. Markers and taps work uniformly.
- **Stored coordinate is in Quartz space (Y-down), but Cocoa is Y-up**: encapsulate the flip in one helper; do not inline it.
- **macOS killed for memory pressure**: on relaunch, the previous `ExecutionLog` is left with `endedAt = null` and `stopReason = "running"` — acceptable; the Logs tab renders it cleanly.
- **Accessibility revoked mid-run**: the engine cannot detect this except by `AXIsProcessTrustedWithOptions` polling; do a check at run-start and re-check before every `iteration`. If denied, abort with `error`.
- **App quit during a run**: gracefully cancel the run, write `endedAt`, then exit. Use `applicationShouldTerminate(_:)` to delay quit until the engine's `finally` block completes (a 300 ms timeout is reasonable).
- **Two scripts with same name**: allowed; IDs disambiguate.
- **Iteration count 0**: prevent in UI (must be `>= 1`); engine should still gracefully bail.
- **Zero-step script**: Start button is disabled; if invoked, engine emits `runStarted` → `runEnded` immediately.
- **Concurrent step writes from editor + recorder**: serialize through the same write chain.

---

## 13. Out-of-scope (deliberately)

- Recording mouse movements / drags / right-clicks — taps only.
- Keyboard input synthesis.
- Image-matching triggers ("tap when this pixel is red").
- Scheduled runs.
- Cloud sync of scripts.
- Multi-user / per-user profiles.
- Apple Silicon vs Intel: a single universal binary covers both.

These are nice-to-have backlog items, not v1 requirements.

---

## 14. Build, signing & distribution

For App Store:

- Enable sandbox + hardened runtime.
- Provide entitlements file (see §11).
- Submit with App Store Connect.
- Note: Apple has historically been picky about apps that "automate UI" — frame the description carefully ("for accessibility purposes, scripted self-testing, repetitive task automation in your own apps") and expect a review back-and-forth.

For Developer ID notarized (direct distribution):

- Enable hardened runtime.
- Sign with `codesign --options runtime --sign "Developer ID Application: <Your Name>" TapScreenTap.app`.
- Notarize via `xcrun notarytool submit ... --wait`.
- Staple: `xcrun stapler staple TapScreenTap.app`.
- Distribute as DMG (preferred) or PKG.

Flutter-specific: the `macos/Runner/Release.entitlements` file needs `com.apple.security.cs.disable-library-validation` if you load any unsigned dylibs (rare in pure Flutter).

---

## 15. Acceptance checklist

A finished macOS build passes when **all** of these are true:

- [ ] Fresh install: welcome+permissions screen shows; Continue is disabled until Accessibility is granted; once granted, Continue lands on the main window.
- [ ] Creating a script via "+" opens the editor with default values; saving makes it active and returns to the scripts list.
- [ ] Recording: clicking the island's record button opens a fullscreen tinted overlay covering all displays; tapping creates a numbered marker; dragging moves it; Undo removes the last; Cancel discards; Save persists and returns to the island.
- [ ] The script editor live-updates the step count and step list when recorder saves.
- [ ] Starting a script clicks at the exact recorded points; with `tapRandomnessEnabled` and a non-zero radius, taps fall inside the disc; the Stop button halts within 200 ms.
- [ ] Logging off: no JSON is written under `logs/`. Logging on: each run replaces the previous log for that script and renders in the Logs tab.
- [ ] Closing the main window does not quit the app; the status-bar item can stop a running script and quit the app.
- [ ] Multi-display: marker placement matches click location for both the same display and a cross-display recording.
- [ ] Active-script selection is cleared on every fresh app launch.
- [ ] The Iterations run mode stops exactly after N iterations and the log reads `iterations_done`.
- [ ] Global random delay adds at most `globalMaxRandomDelaySec * 1000` ms on top of per-step delays.
- [ ] Cocoa Y-flip is consistent: a marker placed at the top of the screen translates to a tap at the top of the screen, not the bottom.
- [ ] Revoking Accessibility mid-run aborts cleanly with an `error` log entry, not a crash.
- [ ] App is notarized and Gatekeeper opens it without warnings (for Developer ID distribution).
