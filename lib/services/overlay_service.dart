import 'dart:async';

import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/script.dart';
import '../models/tap_step.dart';
import 'clicker_channel.dart';
import 'script_repository.dart';

/// Mode change pushed inside the overlay isolate (shareData round-trip is unreliable).
class OverlayModeUpdate {
  final String mode;

  final String? scriptId;
  const OverlayModeUpdate({
    required this.mode,
    this.scriptId,
  });
}

class OverlayService {
  static const recorderFlag = 'recorder';
  static const controlFlag = 'control';
  static const _modeKey = 'overlay_mode';
  static const _scriptIdKey = 'overlay_script_id';

  static bool _transitioning = false;
  static final StreamController<OverlayModeUpdate> _modeUpdatesController =
      StreamController<OverlayModeUpdate>.broadcast();

  /// Emitted in the **main** isolate when the recorder saves and exits, or when
  /// a script run starts/ends so the scripts list can refresh.
  static final StreamController<void> _scriptsChangedController =
      StreamController<void>.broadcast();
  /// ID of the script currently executing in [ClickerEngine], or null when idle.
  /// Set by [OverlayCommandBridge] via Kotlin log events.
  static String? _runningScriptId;
  /// Android overlay plugin treats these as **dp** (see OverlayService.dpToPx).
  /// Size the window to fit content — do not squeeze widgets below their minimums.
  static const int controlWidth = 300;

  static const int controlHeight = 150;
  /// Listen from [_OverlayApp] only (overlay isolate).
  static Stream<OverlayModeUpdate> get modeUpdates =>
      _modeUpdatesController.stream;
  static Stream<dynamic> get overlayListener =>
      FlutterOverlayWindow.overlayListener;

  static String? get runningScriptId => _runningScriptId;

  static Stream<void> get scriptsChanged => _scriptsChangedController.stream;

  /// Push active script to overlay (SharedPreferences is unreliable across engines).
  static Future<void> broadcastActiveScript() async {
    final repo = ScriptRepository();
    final script = await repo.getActiveScript();
    debugLog('broadcastActiveScript: sending script=${script?.id} (${script?.name})');
    await notifyOverlay({
      'action': 'activeScriptUpdated',
      'script': script?.toJson(),
    });
  }
  static void debugLog(String msg) {
    // ignore: avoid_print
    print('[OverlayService] $msg');
  }

  /// Shows the control island if overlay permission is granted.
  static Future<void> ensureControlOverlay() async {
    if (!await isPermissionGranted()) return;

    final prefs = await SharedPreferences.getInstance();
    final active = await FlutterOverlayWindow.isActive();
    final inRecorder = prefs.getString(_modeKey) == recorderFlag;

    // Live fullscreen recorder — do not replace it.
    if (inRecorder && active) return;

    // Overlay missing or stale recorder prefs — (re)create the island.
    if (!active || inRecorder) {
      await showControl();
      return;
    }

    // Island already visible — refresh data only. Calling showOverlay again
    // destroys and recreates the native window (causes flash / disappearance).
    await prefs.setString(_modeKey, controlFlag);
    await prefs.remove(_scriptIdKey);
    await notifyOverlay({'mode': controlFlag});
    await broadcastActiveScript();
  }

  static Future<bool> isPermissionGranted() =>
      FlutterOverlayWindow.isPermissionGranted();

  static Future<void> notifyOverlay(Map<String, dynamic> data) async {
    await FlutterOverlayWindow.shareData(data);
  }

  static void notifyScriptsChanged() {
    if (!_scriptsChangedController.isClosed) _scriptsChangedController.add(null);
  }

  static RecorderPayload? parseRecorderPayload(dynamic data) {
    if (data is! Map) return null;
    final mode = data['mode'] as String?;
    if (mode != recorderFlag) return null;
    final scriptId = data['scriptId'] as String?;
    if (scriptId == null) return null;
    final stepsRaw = data['steps'] as List<dynamic>?;
    final steps = stepsRaw
            ?.map((e) => TapStep.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList() ??
        [];
    return RecorderPayload(scriptId: scriptId, steps: steps);
  }

  static Future<Map<String, dynamic>> readLaunchConfig() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'mode': prefs.getString(_modeKey) ?? controlFlag,
      'scriptId': prefs.getString(_scriptIdKey),
    };
  }

  static Future<void> requestPermission() =>
      FlutterOverlayWindow.requestPermission();

  /// Overlay → main app (picked up by [OverlayCommandBridge]).
  static Future<void> sendCommand(Map<String, dynamic> data) async {
    await FlutterOverlayWindow.shareData(data);
  }

  static void setRunningScriptId(String? id) => _runningScriptId = id;

  static Future<void> showControl() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, controlFlag);
    await prefs.remove(_scriptIdKey);
    await _showControlWindow();
  }

  static Future<void> switchToControl() async {
    debugLog('switchToControl: start, transitioning=$_transitioning');
    await _withOverlayLock(() async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modeKey, controlFlag);
      await prefs.remove(_scriptIdKey);

      // Cached overlay engine keeps Dart state across close/show. Switch UI
      // to control *before* resizing the window, or recorder markers/toolbar
      // render inside the small island.
      _emitModeUpdate(const OverlayModeUpdate(mode: controlFlag));

      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.closeOverlay();
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }

      await FlutterOverlayWindow.showOverlay(
        height: controlHeight,
        width: controlWidth,
        alignment: OverlayAlignment.centerRight,
        flag: OverlayFlag.defaultFlag,
        overlayTitle: 'Tap Control',
        overlayContent: 'Run scripts',
        enableDrag: true,
      );

      _emitModeUpdate(const OverlayModeUpdate(mode: controlFlag));

      await Future<void>.delayed(const Duration(milliseconds: 350));
      await ClickerChannel.ensureOverlayEngineRegistered();
      debugLog('switchToControl: done');
    });
  }

  static Future<void> switchToRecorder(Script script) async {
    debugLog('switchToRecorder: start, script=${script.id}, transitioning=$_transitioning');

    await _withOverlayLock(() async {
      debugLog('switchToRecorder: lock acquired, writing prefs');
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_modeKey, recorderFlag);
      await prefs.setString(_scriptIdKey, script.id);

      // Close the existing overlay first so Android's onDestroy clears
      // windowManager. If we call showOverlay on a running service Android
      // calls stopSelf() inside onStartCommand which then destroys the newly
      // created fullscreen window in onDestroy.
      if (await FlutterOverlayWindow.isActive()) {
        debugLog('switchToRecorder: closing existing overlay');
        await FlutterOverlayWindow.closeOverlay();
        await Future<void>.delayed(const Duration(milliseconds: 350));
      }

      // Use topLeft + startPosition(0,0) to avoid two bugs in the plugin's Java:
      //  1. OverlayAlignment.center uses Gravity.CENTER, which misinterprets the
      //     y-offset as "from screen center" rather than "from screen top", cutting
      //     off the bottom of the screen.
      //  2. When startY == DEFAULT_XY the service sets dy = -statusBarHeightPx()
      //     (px value) then calls dpToPx(dy), double-converting it by density.
      //     Passing startPosition(0,0) bypasses this path entirely → params.y = 0,
      //     which positions the window at the physical screen top.
      debugLog('switchToRecorder: calling showOverlay fullCover (topLeft, y=0)');
      await FlutterOverlayWindow.showOverlay(
        height: WindowSize.fullCover,
        width: WindowSize.matchParent,
        alignment: OverlayAlignment.topLeft,
        startPosition: const OverlayPosition(0, 0),
        flag: OverlayFlag.defaultFlag,
        overlayTitle: 'Tap Recorder',
        overlayContent: 'Record tap positions',
        enableDrag: false,
      );
      debugLog('switchToRecorder: emitting modeUpdate');
      _emitModeUpdate(OverlayModeUpdate(
        mode: recorderFlag,
        scriptId: script.id,
      ));

      await Future<void>.delayed(const Duration(milliseconds: 350));
      await ClickerChannel.ensureOverlayEngineRegistered();
      debugLog('switchToRecorder: done');
    });
    debugLog('switchToRecorder: returned from lock (transitioning=$_transitioning)');
  }

  static void _emitModeUpdate(OverlayModeUpdate update) {
    if (!_modeUpdatesController.isClosed) {
      _modeUpdatesController.add(update);
    }
  }

  static Future<void> _showControlWindow() async {
    debugLog('_showControlWindow: enter');
    await _withOverlayLock(() async {
      await FlutterOverlayWindow.showOverlay(
        height: controlHeight,
        width: controlWidth,
        alignment: OverlayAlignment.centerRight,
        flag: OverlayFlag.defaultFlag,
        overlayTitle: 'Tap Control',
        overlayContent: 'Run scripts',
        enableDrag: true,
      );

      await Future<void>.delayed(const Duration(milliseconds: 400));
      await ClickerChannel.ensureOverlayEngineRegistered();
      // This runs in the MAIN isolate, so _emitModeUpdate is invisible to the
      // overlay isolate's _OverlayApp. Use notifyOverlay (shareData) instead —
      // it is cross-isolate and safe to await from the main isolate.
      await notifyOverlay({'mode': controlFlag});
      await broadcastActiveScript();
    });
  }

  static Future<void> _withOverlayLock(Future<void> Function() action) async {
    var waitedMs = 0;
    const maxWaitMs = 5000;
    const stepMs = 50;
    debugLog('_withOverlayLock: enter, transitioning=$_transitioning');
    while (_transitioning && waitedMs < maxWaitMs) {
      await Future<void>.delayed(const Duration(milliseconds: stepMs));
      waitedMs += stepMs;
    }
    debugLog('_withOverlayLock: waited ${waitedMs}ms, transitioning=$_transitioning');
    if (_transitioning) {
      debugLog('_withOverlayLock: TIMED OUT, bailing');
      return;
    }

    _transitioning = true;
    debugLog('_withOverlayLock: running action');
    try {
      await action();
    } catch (e, st) {
      debugLog('_withOverlayLock: action threw: $e\n$st');
      rethrow;
    } finally {
      _transitioning = false;
    }
  }
}

class RecorderPayload {
  final String scriptId;

  final List<TapStep> steps;
  const RecorderPayload({required this.scriptId, required this.steps});
}
