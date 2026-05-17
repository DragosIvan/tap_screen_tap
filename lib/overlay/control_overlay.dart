import 'package:flutter/material.dart';

import '../models/script.dart';
import '../services/clicker_channel.dart';
import '../services/overlay_service.dart';
import '../services/script_repository.dart';

class ControlOverlay extends StatefulWidget {
  const ControlOverlay({
    super.key,
    required this.isClicking,
    this.activeScript,
  });

  final bool isClicking;
  final Script? activeScript;

  @override
  State<ControlOverlay> createState() => _ControlOverlayState();
}

class _ControlOverlayState extends State<ControlOverlay> {
  Script? get _active => widget.activeScript;

  Future<void> _start() async {
    final script = _active;
    if (script == null || script.steps.isEmpty) return;

    final iterations = script.runMode.type == RunModeType.iterations
        ? script.runMode.count
        : -1;

    await ClickerChannel.startClicking(
      script: script,
      iterations: iterations,
    );
  }

  Future<void> _stop() async {
    await ClickerChannel.stopClicking();
  }

  Future<void> _record() async {
    final id = _active?.id;
    if (id == null) return;
    // Always load from disk — in-memory active script may lack latest steps.
    final script = await ScriptRepository().getById(id);
    if (script == null) return;
    await OverlayService.switchToRecorder(script);
  }

  @override
  Widget build(BuildContext context) {
    final active = _active;

    return SizedBox(
      width: OverlayService.controlWidth.toDouble(),
      height: OverlayService.controlHeight.toDouble(),
      child: Material(
        elevation: 4,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.hardEdge,
        color: Theme.of(context).colorScheme.surfaceContainerHigh,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                active?.name ?? 'No active script',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: active != null
                      ? null
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  _ActionIcon(
                    tooltip: 'Start',
                    icon: Icons.play_arrow,
                    filled: true,
                    enabled: !widget.isClicking &&
                        active != null &&
                        active.steps.isNotEmpty,
                    onPressed: _start,
                  ),
                  _ActionIcon(
                    tooltip: 'Stop',
                    icon: Icons.stop,
                    enabled: widget.isClicking,
                    onPressed: _stop,
                  ),
                  _ActionIcon(
                    tooltip: 'Record taps',
                    icon: Icons.gps_fixed,
                    enabled: !widget.isClicking && active != null,
                    onPressed: _record,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon({
    required this.tooltip,
    required this.icon,
    required this.enabled,
    required this.onPressed,
    this.filled = false,
  });

  final String tooltip;
  final IconData icon;
  final bool enabled;
  final VoidCallback onPressed;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final button = filled
        ? IconButton.filled(
            onPressed: enabled ? onPressed : null,
            icon: Icon(icon, size: 18),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
          )
        : IconButton(
            onPressed: enabled ? onPressed : null,
            icon: Icon(icon, size: 18),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: 32,
              minHeight: 32,
            ),
          );

    return Expanded(child: Tooltip(message: tooltip, child: button));
  }
}

