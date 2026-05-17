import 'dart:async';

import 'package:flutter/material.dart';

import 'models/script.dart';
import 'overlay/control_overlay.dart';
import 'overlay/recorder_overlay.dart';
import 'screens/onboarding_screen.dart';
import 'services/clicker_channel.dart';
import 'services/execution_log_writer.dart';
import 'services/log_repository.dart';
import 'services/overlay_command_bridge.dart';
import 'services/overlay_service.dart';
import 'services/script_repository.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Clear the persisted active-script selection on every fresh app launch so
  // neither the scripts tab nor the island shows a stale selection.
  await ScriptRepository().clearActiveScript();
  runApp(const TapScreenTapApp());
}

@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _OverlayApp());
}

class TapScreenTapApp extends StatefulWidget {
  const TapScreenTapApp({super.key});

  @override
  State<TapScreenTapApp> createState() => _TapScreenTapAppState();
}

class _TapScreenTapAppState extends State<TapScreenTapApp> {
  final _logWriter = ExecutionLogWriter(LogRepository());
  final _overlayBridge = OverlayCommandBridge();

  @override
  void initState() {
    super.initState();
    _logWriter.startListening();
    _overlayBridge.start();
  }

  @override
  void dispose() {
    _logWriter.dispose();
    _overlayBridge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tap Screen Tap',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const OnboardingScreen(),
    );
  }
}

class _OverlayApp extends StatefulWidget {
  const _OverlayApp();

  @override
  State<_OverlayApp> createState() => _OverlayAppState();
}

class _OverlayAppState extends State<_OverlayApp> {
  String _mode = OverlayService.controlFlag;
  String? _scriptId;
  bool _ready = false;
  bool _isClicking = false;
  int _controlRefreshToken = 0;
  Script? _activeScript;
  StreamSubscription<dynamic>? _listenerSub;
  StreamSubscription<Map<dynamic, dynamic>>? _clickerSub;
  StreamSubscription<OverlayModeUpdate>? _modeSub;

  @override
  void initState() {
    super.initState();
    _listenerSub = OverlayService.overlayListener.listen(_onMessage);
    _clickerSub = ClickerChannel.eventStream.listen(_onClickerEvent);
    _modeSub = OverlayService.modeUpdates.listen(_applyModeUpdate);
    _bootstrap();
    _syncClickingState();
  }

  void _applyModeUpdate(OverlayModeUpdate update) {
    // ignore: avoid_print
    print('[OverlayApp] _applyModeUpdate: mode=${update.mode}, mounted=$mounted');
    if (!mounted) return;
    setState(() {
      _mode = update.mode;
      if (update.mode == OverlayService.recorderFlag) {
        _scriptId = update.scriptId;
      } else {
        _scriptId = null;
        _controlRefreshToken++;
      }
    });
  }

  Future<void> _syncClickingState() async {
    try {
      final clicking = await ClickerChannel.isClicking();
      if (mounted) setState(() => _isClicking = clicking);
    } catch (_) {}
  }

  void _onClickerEvent(Map<dynamic, dynamic> event) {
    if (event['event'] == 'clickingStateChanged') {
      setState(() => _isClicking = event['isClicking'] as bool? ?? false);
    }
  }

  Future<void> _bootstrap() async {
    final config = await OverlayService.readLaunchConfig();
    if (!mounted) return;
    final rawMode = config['mode'] as String? ?? OverlayService.controlFlag;
    final rawScriptId = config['scriptId'] as String?;

    // Only honour a recorder mode from prefs when there is an explicit scriptId.
    // Stale `recorder` prefs from a crashed/killed session would otherwise
    // render the recorder toolbar inside the small island window.
    final mode = (rawMode == OverlayService.recorderFlag && rawScriptId != null)
        ? OverlayService.recorderFlag
        : OverlayService.controlFlag;

    setState(() {
      _mode = mode;
      _scriptId = mode == OverlayService.recorderFlag ? rawScriptId : null;
      _ready = true;
    });
  }

  void _onMessage(dynamic data) {
    // ignore: avoid_print
    print('[OverlayApp] _onMessage: $data');
    if (data is Map) {
      final action = data['action'] as String?;
      if (action == 'clickingState') {
        setState(() => _isClicking = data['isClicking'] as bool? ?? false);
        return;
      }
      if (action == 'activeScriptUpdated') {
        final scriptMap = data['script'];
        final incoming = scriptMap != null
            ? Script.fromJson(Map<String, dynamic>.from(scriptMap as Map))
            : null;
        setState(() {
          // While a script is running, never blank out the label — only apply
          // a null update when the engine is idle.
          if (incoming != null || !_isClicking) {
            _activeScript = incoming;
          }
          _controlRefreshToken++;
        });
        return;
      }
    }

    final payload = OverlayService.parseRecorderPayload(data);
    if (payload != null) {
      setState(() {
        _mode = OverlayService.recorderFlag;
        _scriptId = payload.scriptId;
      });
      return;
    }
    if (data is Map && data['mode'] == OverlayService.controlFlag) {
      setState(() {
        _mode = OverlayService.controlFlag;
        _controlRefreshToken++;
      });
    }
  }

  @override
  void dispose() {
    _listenerSub?.cancel();
    _clickerSub?.cancel();
    _modeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
        visualDensity: VisualDensity.compact,
      ),
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.noScaling,
          ),
          child: child!,
        );
      },
      home: _buildOverlayHome(),
    );
  }

  Widget _buildOverlayHome() {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_mode == OverlayService.recorderFlag && _scriptId != null) {
      return SizedBox.expand(
        child: RecorderOverlay(
          key: ValueKey('recorder_$_scriptId'),
          scriptId: _scriptId,
        ),
      );
    }
    return ColoredBox(
      color: Colors.transparent,
      child: Align(
        alignment: Alignment.centerRight,
        child: ControlOverlay(
          key: ValueKey('control_$_controlRefreshToken'),
          isClicking: _isClicking,
          activeScript: _activeScript,
        ),
      ),
    );
  }
}
