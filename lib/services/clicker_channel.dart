import 'dart:async';

import 'package:flutter/services.dart';

import '../models/script.dart';

class ClickerChannel {
  static const _method = MethodChannel('com.example.tap_screen_tap/clicker');
  static const _events = EventChannel('com.example.tap_screen_tap/clicker_events');

  static final Stream<Map<dynamic, dynamic>> eventStream =
      _events.receiveBroadcastStream().map((e) => Map<dynamic, dynamic>.from(e as Map));

  static Future<bool> isAccessibilityEnabled() async {
    final result = await _method.invokeMethod<bool>('isAccessibilityEnabled');
    return result ?? false;
  }

  static Future<void> openAccessibilitySettings() =>
      _method.invokeMethod('openAccessibilitySettings');

  static Future<bool> canDrawOverlays() async {
    final result = await _method.invokeMethod<bool>('canDrawOverlays');
    return result ?? false;
  }

  static Future<void> openOverlaySettings() =>
      _method.invokeMethod('openOverlaySettings');

  static Future<void> startClicking({
    required Script script,
    required int iterations,
  }) =>
      _method.invokeMethod('startClicking', {
        'script': script.toEngineMap(),
        'iterations': iterations,
      });

  static Future<void> stopClicking() => _method.invokeMethod('stopClicking');

  static Future<bool> isClicking() async {
    final result = await _method.invokeMethod<bool>('isClicking');
    return result ?? false;
  }

  /// Registers clicker channels on the overlay Flutter engine (main isolate only).
  static Future<void> ensureOverlayEngineRegistered() async {
    try {
      await _method.invokeMethod<void>('ensureOverlayEngineRegistered');
    } catch (_) {}
  }

  /// Signals that the recorder saved its steps. Routed via Kotlin's
  /// [ClickerEventSink] so it reaches the main engine even after the overlay
  /// window is closed and recreated.
  static Future<void> notifyRecorderDone() async {
    try {
      await _method.invokeMethod<void>('notifyRecorderDone');
    } catch (_) {}
  }
}
