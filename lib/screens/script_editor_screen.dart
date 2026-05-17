import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/script.dart';
import '../models/tap_step.dart';
import '../services/overlay_service.dart';
import '../services/script_repository.dart';

class ScriptEditorScreen extends StatefulWidget {
  final String scriptId;

  final bool isNew;

  final Script? draft;
  ScriptEditorScreen.create({super.key, required Script draft})
      : scriptId = draft.id,
        isNew = true,
        draft = draft;
  const ScriptEditorScreen.edit({super.key, required this.scriptId})
      : isNew = false,
        draft = null;

  @override
  State<ScriptEditorScreen> createState() => _ScriptEditorScreenState();
}

class _ScriptEditorScreenState extends State<ScriptEditorScreen> {
  final _repo = ScriptRepository();
  final _nameController = TextEditingController();
  final _iterationsController = TextEditingController();
  final _globalRadiusController = TextEditingController();
  Script? _script;
  bool _loading = true;
  bool _saving = false;
  StreamSubscription<void>? _scriptsSub;

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    final script = _script;
    if (script == null) {
      return const Scaffold(body: Center(child: Text('Script not found')));
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isNew ? 'New script' : 'Edit script'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _save,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Script name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Text('Global settings', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SwitchListTile(
            title: const Text('Tap randomness'),
            subtitle: const Text('Random point inside circle per tap'),
            value: script.tapRandomnessEnabled,
            onChanged: (v) =>
                _updateScript((s) => s.copyWith(tapRandomnessEnabled: v)),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _globalRadiusController,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Global radius (px)',
              hintText: '0 = disabled',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) {
              final n = int.tryParse(v);
              _updateScript((s) => s.copyWith(globalRadiusPx: n ?? 0));
            },
          ),
          const SizedBox(height: 32),
          _SliderRow(
            label: 'Default min delay (ms)',
            value: script.defaultMinDelayMs.toDouble(),
            min: 0,
            max: 10000,
            divisions: 100,
            onChanged: (v) =>
                _updateScript((s) => s.copyWith(defaultMinDelayMs: v.round())),
          ),
          _SliderRow(
            label: 'Default max delay (ms)',
            value: script.defaultMaxDelayMs.toDouble(),
            min: 0,
            max: 15000,
            divisions: 150,
            onChanged: (v) =>
                _updateScript((s) => s.copyWith(defaultMaxDelayMs: v.round())),
          ),
          SwitchListTile(
            title: const Text('Global random delay'),
            subtitle: const Text('Adds 0..max seconds to each wait'),
            value: script.globalRandomDelayEnabled,
            onChanged: (v) =>
                _updateScript((s) => s.copyWith(globalRandomDelayEnabled: v)),
          ),
          _SliderRow(
            label: 'Max random delay (sec)',
            value: script.globalMaxRandomDelaySec.toDouble(),
            min: 0,
            max: 30,
            divisions: 30,
            onChanged: (v) => _updateScript(
              (s) => s.copyWith(globalMaxRandomDelaySec: v.round()),
            ),
          ),
          _SliderRow(
            label: 'End delay (ms)',
            value: script.endDelayMs.toDouble(),
            min: 0,
            max: 10000,
            divisions: 100,
            onChanged: (v) =>
                _updateScript((s) => s.copyWith(endDelayMs: v.round())),
          ),
          const SizedBox(height: 8),
          SegmentedButton<RunModeType>(
            segments: const [
              ButtonSegment(
                value: RunModeType.untilStopped,
                label: Text('Until stopped'),
              ),
              ButtonSegment(
                value: RunModeType.iterations,
                label: Text('Iterations'),
              ),
            ],
            selected: {script.runMode.type},
            onSelectionChanged: (set) {
              final type = set.first;
              if (type == RunModeType.untilStopped) {
                _updateScript((s) => s.copyWith(runMode: const RunMode.untilStopped()));
              } else {
                final current = _script;
                final count = current?.runMode.type == RunModeType.iterations
                    ? current!.runMode.count
                    : 3;
                _iterationsController.text = '$count';
                _updateScript(
                  (s) => s.copyWith(runMode: RunMode.iterations(count)),
                );
              }
            },
          ),
          if (script.runMode.type == RunModeType.iterations) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _iterationsController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                labelText: 'Number of iterations',
                hintText: 'e.g. 10',
                border: OutlineInputBorder(),
              ),
              onChanged: (v) {
                final n = int.tryParse(v);
                if (n != null && n > 0) {
                  _updateScript((s) => s.copyWith(runMode: RunMode.iterations(n)));
                }
              },
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Steps (${script.steps.length})',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (script.steps.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No steps — use Record taps on the floating island'),
              ),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: script.steps.length,
              onReorder: (oldIndex, newIndex) {
                _updateScript((s) {
                  final steps = List<TapStep>.from(s.steps);
                  if (newIndex > oldIndex) newIndex--;
                  final item = steps.removeAt(oldIndex);
                  steps.insert(newIndex, item);
                  return s.copyWith(steps: steps);
                });
              },
              itemBuilder: (context, index) {
                final step = script.steps[index];
                return _StepTile(
                  key: ValueKey(
                    'step_${step.x}_${step.y}_${step.delayAfterMs}_${step.radiusPx}',
                  ),
                  index: index,
                  step: step,
                  onChanged: (step) {
                    _updateScript((s) {
                      final steps = List<TapStep>.from(s.steps);
                      steps[index] = step;
                      return s.copyWith(steps: steps);
                    });
                  },
                  onDelete: () {
                    _updateScript((s) {
                      final steps = List<TapStep>.from(s.steps);
                      steps.removeAt(index);
                      return s.copyWith(steps: steps);
                    });
                  },
                );
              },
            ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _scriptsSub?.cancel();
    _nameController.dispose();
    _iterationsController.dispose();
    _globalRadiusController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load();
    _scriptsSub = OverlayService.scriptsChanged.listen((_) {
      if (mounted && !widget.isNew) _load();
    });
  }

  Future<void> _load() async {
    if (widget.isNew && widget.draft != null) {
      setState(() {
        _script = widget.draft;
        _nameController.text = widget.draft!.name;
        _loading = false;
      });
      return;
    }
    final script = await _repo.getById(widget.scriptId);
    if (!mounted) return;
    setState(() {
      _script = script;
      _nameController.text = script?.name ?? '';
      if (script?.runMode.type == RunModeType.iterations) {
        _iterationsController.text = '${script!.runMode.count}';
      }
      _globalRadiusController.text =
          script?.globalRadiusPx == 0 ? '' : '${script?.globalRadiusPx ?? ''}';
      _loading = false;
    });
  }

  Future<void> _save() async {
    final script = _script;
    if (script == null) return;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a script name')),
      );
      return;
    }

    setState(() => _saving = true);
    final updated = script.copyWith(name: name);
    await _repo.save(updated);
    if (widget.isNew) {
      await _repo.setActiveScriptId(updated.id);
    }
    await OverlayService.broadcastActiveScript();
    if (!mounted) return;
    setState(() => _saving = false);

    if (widget.isNew) {
      Navigator.of(context).pop(true);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Script saved')),
    );
  }

  void _updateScript(Script Function(Script) fn) {
    final s = _script;
    if (s == null) return;
    setState(() => _script = fn(s));
  }
}

class _SliderRow extends StatelessWidget {
  final String label;

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.divisions,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: ${value.round()}'),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          label: value.round().toString(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _StepTile extends StatefulWidget {
  final int index;

  final TapStep step;
  final ValueChanged<TapStep> onChanged;
  final VoidCallback onDelete;
  const _StepTile({
    super.key,
    required this.index,
    required this.step,
    required this.onChanged,
    required this.onDelete,
  });

  @override
  State<_StepTile> createState() => _StepTileState();
}

class _StepTileState extends State<_StepTile> {
  bool _expanded = false;
  late final TextEditingController _delayController;
  late final TextEditingController _radiusController;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: widget.key,
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          ListTile(
            leading: ReorderableDragStartListener(
              index: widget.index,
              child: const Icon(Icons.drag_handle),
            ),
            title: Text(
              'Step ${widget.index + 1}: (${widget.step.x.toStringAsFixed(0)}, ${widget.step.y.toStringAsFixed(0)})',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                  onPressed: () => setState(() => _expanded = !_expanded),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  onPressed: widget.onDelete,
                ),
              ],
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                children: [
                  TextField(
                    controller: _delayController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Delay after (ms)',
                      hintText: 'Empty = use default range',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      final ms = int.tryParse(v);
                      widget.onChanged(
                        widget.step.copyWith(
                          delayAfterMs: ms,
                          clearDelayAfterMs: v.isEmpty,
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _radiusController,
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(
                      labelText: 'Radius override (px)',
                      hintText: 'Empty = use global radius',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) {
                      final px = int.tryParse(v);
                      widget.onChanged(
                        widget.step.copyWith(
                          radiusPx: px,
                          clearRadiusPx: v.isEmpty,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _StepTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.step.delayAfterMs != widget.step.delayAfterMs) {
      _delayController.text = widget.step.delayAfterMs?.toString() ?? '';
    }
    if (oldWidget.step.radiusPx != widget.step.radiusPx) {
      _radiusController.text = widget.step.radiusPx?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _delayController.dispose();
    _radiusController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _delayController = TextEditingController(
      text: widget.step.delayAfterMs?.toString() ?? '',
    );
    _radiusController = TextEditingController(
      text: widget.step.radiusPx?.toString() ?? '',
    );
  }
}
