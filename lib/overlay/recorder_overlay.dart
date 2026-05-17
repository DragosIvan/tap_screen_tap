import 'package:flutter/material.dart';

import '../models/script.dart';
import '../models/tap_step.dart';
import '../services/clicker_channel.dart';
import '../services/overlay_service.dart';
import '../services/script_repository.dart';

class RecorderOverlay extends StatefulWidget {
  const RecorderOverlay({super.key, this.scriptId});

  final String? scriptId;

  @override
  State<RecorderOverlay> createState() => _RecorderOverlayState();
}

class _RecorderOverlayState extends State<RecorderOverlay> {
  static const double _defaultMarkerDiameter = 36;

  final _repo = ScriptRepository();
  String? _scriptId;
  List<TapStep> _steps = [];
  bool _tapRandomnessEnabled = false;
  int _globalRadiusPx = 0;
  bool _loading = true;
  String? _error;
  int? _draggingIndex;
  Future<void> _saveChain = Future.value();

  @override
  void initState() {
    super.initState();
    _scriptId = widget.scriptId;
    _loadScript();
  }

  @override
  void didUpdateWidget(covariant RecorderOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scriptId != widget.scriptId) {
      _scriptId = widget.scriptId;
      _loadScript();
    }
  }

  Future<void> _loadScript() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (_scriptId == null) {
        setState(() {
          _loading = false;
          _error = 'No script selected';
        });
        return;
      }

      final script = await _repo.getById(_scriptId!);
      if (script == null) {
        setState(() {
          _loading = false;
          _error = 'Script not found';
        });
        return;
      }

      setState(() {
        _tapRandomnessEnabled = script.tapRandomnessEnabled;
        _globalRadiusPx = script.globalRadiusPx;
        _steps = List.from(script.steps);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load script: $e';
      });
    }
  }

  /// Diameter in logical pixels. Matches [ClickerEngine] tap spread: step
  /// [TapStep.radiusPx] overrides [Script.globalRadiusPx] when randomness is on.
  double _markerDiameter(TapStep step) {
    final stepRadius = step.radiusPx;
    if (stepRadius != null && stepRadius > 0) {
      return stepRadius * 2;
    }
    if (_tapRandomnessEnabled && _globalRadiusPx > 0) {
      return _globalRadiusPx * 2;
    }
    return _defaultMarkerDiameter;
  }

  Future<void> _saveSteps() async {
    if (_scriptId == null) return;
    final id = _scriptId!;
    final steps = List<TapStep>.from(_steps);
    _saveChain = _saveChain.then((_) async {
      try {
        final ok = await _repo.updateSteps(id, steps);
        if (!ok) {
          // ignore: avoid_print
          print('[RecorderOverlay] _saveSteps: script not found for id=$id');
        }
      } catch (e, st) {
        // ignore: avoid_print
        print('[RecorderOverlay] _saveSteps ERROR: $e\n$st');
      }
    });
    await _saveChain;
  }

  void _addPoint(Offset position) {
    if (_draggingIndex != null) return;
    setState(() {
      _steps = [
        ..._steps,
        TapStep(x: position.dx, y: position.dy),
      ];
    });
    _saveSteps();
  }

  void _movePoint(int index, Offset delta) {
    final step = _steps[index];
    setState(() {
      _steps[index] = step.copyWith(
        x: step.x + delta.dx,
        y: step.y + delta.dy,
      );
    });
  }

  Future<void> _undo() async {
    if (_steps.isEmpty) return;
    setState(() => _steps = _steps.sublist(0, _steps.length - 1));
    await _saveSteps();
  }

  Future<void> _finish() async {
    await _saveSteps();
    await ClickerChannel.notifyRecorderDone();
    await OverlayService.switchToControl();
  }

  Widget _buildMarker(int index) {
    final step = _steps[index];
    final diameter = _markerDiameter(step);
    final half = diameter / 2;
    final isDragging = _draggingIndex == index;
    final labelSize = (diameter * 0.38).clamp(10.0, 18.0);

    return Positioned(
      left: step.x - half,
      top: step.y - half,
      child: GestureDetector(
        onPanStart: (_) => setState(() => _draggingIndex = index),
        onPanUpdate: (d) => _movePoint(index, d.delta),
        onPanEnd: (_) {
          setState(() => _draggingIndex = null);
          _saveSteps();
        },
        child: Material(
          elevation: isDragging ? 8 : 2,
          shape: const CircleBorder(),
          color: Colors.redAccent.withValues(alpha: 0.85),
          child: SizedBox(
            width: diameter,
            height: diameter,
            child: Center(
              child: Text(
                '${index + 1}',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: labelSize,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: Colors.black54,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        backgroundColor: Colors.black87,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _finish,
                  child: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black26,
      body: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapDown: (d) => _addPoint(d.globalPosition),
              child: const SizedBox.expand(),
            ),
            ...List.generate(_steps.length, _buildMarker),
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 16,
              right: 16,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black87,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'Tap empty area to add · Drag markers to move (${_steps.length} steps)',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: MediaQuery.of(context).padding.bottom + 16,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.tonal(
                      onPressed: _steps.isEmpty ? null : _undo,
                      child: const Text('Undo'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _finish,
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
