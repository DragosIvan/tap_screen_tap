import 'dart:async';

import '../models/script.dart';
import 'clicker_channel.dart';
import 'overlay_service.dart';

/// Handles overlay → main-app commands (overlay isolate has no MethodChannel).
class OverlayCommandBridge {
  StreamSubscription<dynamic>? _overlaySub;
  StreamSubscription<Map<dynamic, dynamic>>? _clickerSub;

  void start() {
    _overlaySub ??= OverlayService.overlayListener.listen(_onOverlayMessage);
    _clickerSub ??= ClickerChannel.eventStream.listen(_onClickerEvent);
  }

  void dispose() {
    _overlaySub?.cancel();
    _overlaySub = null;
    _clickerSub?.cancel();
    _clickerSub = null;
  }

  Future<void> _onOverlayMessage(dynamic data) async {
    if (data is! Map) return;
    final action = data['action'] as String?;
    // ignore: avoid_print
    print('[OverlayBridge] _onOverlayMessage: action=$action');
    if (action == 'startClicking') {
      final scriptMap = data['script'] as Map?;
      final iterations = (data['iterations'] as num?)?.toInt() ?? -1;
      if (scriptMap == null) return;
      final script = Script.fromJson(Map<String, dynamic>.from(scriptMap));
      await ClickerChannel.startClicking(
        script: script,
        iterations: iterations,
      );
      return;
    }
    if (action == 'stopClicking') {
      await ClickerChannel.stopClicking();
      await OverlayService.notifyOverlay({
        'action': 'clickingState',
        'isClicking': false,
      });
      return;
    }
    if (action == 'queryClicking') {
      final clicking = await ClickerChannel.isClicking();
      await OverlayService.notifyOverlay({
        'action': 'clickingState',
        'isClicking': clicking,
      });
      return;
    }
  }

  void _onClickerEvent(Map<dynamic, dynamic> event) {
    final name = event['event'] as String?;
    if (name == 'clickingStateChanged') {
      // ignore: avoid_print
      print('[OverlayBridge] clickingStateChanged: isClicking=${event['isClicking']}');
      OverlayService.notifyOverlay({
        'action': 'clickingState',
        'isClicking': event['isClicking'] ?? false,
      });
      return;
    }
    if (name == 'recorderDone') {
      // ignore: avoid_print
      print('[OverlayBridge] recorderDone — refreshing scripts list and island');
      OverlayService.notifyScriptsChanged();
      unawaited(OverlayService.broadcastActiveScript());
      return;
    }
    if (name == 'logEvent') {
      final entryMap = event['entry'] as Map?;
      final type = entryMap?['type'] as String?;
      final scriptId = event['scriptId'] as String?;
      if (type == 'runStarted') {
        // ignore: avoid_print
        print('[OverlayBridge] runStarted: scriptId=$scriptId');
        OverlayService.setRunningScriptId(scriptId);
        OverlayService.notifyScriptsChanged();
      } else if (type == 'runEnded' || type == 'error') {
        // ignore: avoid_print
        print('[OverlayBridge] $type: run finished for scriptId=$scriptId');
        OverlayService.setRunningScriptId(null);
        OverlayService.notifyScriptsChanged();
      }
    }
  }
}
