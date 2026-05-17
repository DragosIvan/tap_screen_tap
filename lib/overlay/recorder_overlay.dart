import 'package:flutter/material.dart';

import '../models/tap_step.dart';
import '../services/clicker_channel.dart';
import '../services/overlay_service.dart';
import '../services/screen_coordinates.dart';
import '../services/script_repository.dart';

class RecorderOverlay extends StatefulWidget {
  final String? scriptId;

  const RecorderOverlay({super.key, this.scriptId});

  @override
  State<RecorderOverlay> createState() => _RecorderOverlayState();
}

class _RecorderOverlayState extends State<RecorderOverlay> {
  static const double _defaultMarkerDiameter = 36;

  final _repo = ScriptRepository();
  final _stackKey = GlobalKey();
  String? _scriptId;
  List<TapStep> _steps = [];
  bool _tapRandomnessEnabled = false;
  int _globalRadiusPx = 0;
  ScreenCoordinateMapper? _mapper;
  bool _loading = true;
  String? _error;
  int? _draggingIndex;

  RenderBox? get _overlayBox {
    final box = _stackKey.currentContext?.findRenderObject();
    return box is RenderBox ? box : null;
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
                  onPressed: _cancel,
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
      body: Builder(
        builder: (context) {
          final mq = MediaQuery.of(context);
          final topPad = mq.padding.top;
          // ignore: avoid_print
          print('[RecorderOverlay] build: size=${mq.size}  padding=${mq.padding}  viewPadding=${mq.viewPadding}  devicePixelRatio=${mq.devicePixelRatio}  topPad=$topPad');
          return SizedBox.expand(
            child: Stack(
              key: _stackKey,
              fit: StackFit.expand,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTapDown: (d) => _addPoint(d.localPosition),
                  child: const SizedBox.expand(),
                ),
                ...List.generate(_steps.length, _buildMarker),
              _buildTopBar(context),
            ],
          ),
        );
      },
    ),
  );
  }

  @override
  void didUpdateWidget(covariant RecorderOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scriptId != widget.scriptId) {
      _scriptId = widget.scriptId;
      _loadScript();
    }
  }

  @override
  void initState() {
    super.initState();
    _scriptId = widget.scriptId;
    _loadScript();
  }

  void _addPoint(Offset localPosition) {
    if (_draggingIndex != null) return;
    final box = _overlayBox;
    final mapper = _mapper;
    if (box == null || mapper == null) return;
    final global = box.localToGlobal(localPosition);
    final physical = mapper.overlayLocalToPhysical(box, localPosition);
    // ignore: avoid_print
    print('[RecorderOverlay] addPoint: local=$localPosition  global=$global  physical=$physical');
    setState(() {
      _steps = [
        ..._steps,
        TapStep(x: physical.dx, y: physical.dy),
      ];
    });
  }

  Widget _buildMarker(int index) {
    final step = _steps[index];
    final box = _overlayBox;
    final mapper = _mapper;
    final diameter = _markerDiameter(step);
    final half = diameter / 2;
    final isDragging = _draggingIndex == index;
    final labelSize = (diameter * 0.38).clamp(10.0, 18.0);
    final logical = (box != null && mapper != null)
        ? mapper.physicalToOverlayLocal(box, step.x, step.y)
        : Offset(step.x, step.y);

    return Positioned(
      left: logical.dx - half,
      top: logical.dy - half,
      child: GestureDetector(
        onPanStart: (_) => setState(() => _draggingIndex = index),
        onPanUpdate: (d) => _movePoint(index, d.delta),
        onPanEnd: (_) => setState(() => _draggingIndex = null),
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

  Widget _buildTopBar(BuildContext context) {
    final pad = MediaQuery.paddingOf(context);
    final top = pad.top + 8;
    final left = pad.left + 8;
    final right = pad.right + 8;

    return Positioned(
      top: top,
      left: left,
      right: right,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Info pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Tap to add · Drag to move',
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          // Action buttons
          Material(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Cancel',
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: _cancel,
                ),
                IconButton(
                  tooltip: 'Undo',
                  icon: Icon(
                    Icons.undo,
                    color: _steps.isEmpty ? Colors.white38 : Colors.white,
                  ),
                  onPressed: _steps.isEmpty ? null : _undo,
                ),
                IconButton(
                  tooltip: 'Save',
                  icon: const Icon(Icons.check, color: Colors.white),
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _cancel() async {
    await OverlayService.switchToControl();
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

      final screen = await ClickerChannel.getDisplayMetrics();
      var steps = List<TapStep>.from(script.steps);

      setState(() {
        _tapRandomnessEnabled = script.tapRandomnessEnabled;
        _globalRadiusPx = script.globalRadiusPx;
        _mapper = ScreenCoordinateMapper(screen);
        _loading = false;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _steps = steps);
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'Failed to load script: $e';
      });
    }
  }

  double _markerDiameter(TapStep step) {
    final mapper = _mapper;
    final physicalRadius = step.radiusPx ??
        (_tapRandomnessEnabled && _globalRadiusPx > 0 ? _globalRadiusPx : null);
    if (physicalRadius != null && physicalRadius > 0 && mapper != null) {
      return (physicalRadius * 2) / mapper.density;
    }
    return _defaultMarkerDiameter;
  }

  void _movePoint(int index, Offset delta) {
    final mapper = _mapper;
    if (mapper == null) return;
    final step = _steps[index];
    final d = mapper.overlayDeltaToPhysical(delta);
    setState(() {
      _steps[index] = step.copyWith(
        x: step.x + d.dx,
        y: step.y + d.dy,
      );
    });
  }

  Future<void> _persistSteps() async {
    if (_scriptId == null) return;
    await _repo.updateSteps(_scriptId!, _steps);
  }

  Future<void> _save() async {
    await _persistSteps();
    await ClickerChannel.notifyRecorderDone();
    await OverlayService.switchToControl();
  }

  void _undo() {
    if (_steps.isEmpty) return;
    setState(() => _steps = _steps.sublist(0, _steps.length - 1));
  }
}
