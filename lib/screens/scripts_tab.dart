import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/script.dart';
import '../services/log_repository.dart';
import '../services/overlay_service.dart';
import '../services/script_repository.dart';
import 'script_editor_screen.dart';

class ScriptsTab extends StatefulWidget {
  const ScriptsTab({super.key, required this.onChanged});

  final VoidCallback onChanged;

  @override
  State<ScriptsTab> createState() => _ScriptsTabState();
}

class _ScriptsTabState extends State<ScriptsTab> {
  final _scriptRepo = ScriptRepository();
  final _logRepo = LogRepository();
  List<_ScriptRow> _rows = [];
  String? _activeScriptId;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final scripts = await _scriptRepo.getAll();
    final storedActiveId = await _scriptRepo.getActiveScriptId();
    // While the engine is running, prefer the running script's ID so the row
    // stays highlighted even if the stored selection is momentarily null.
    final activeId = storedActiveId ?? OverlayService.runningScriptId;
    final rows = <_ScriptRow>[];
    for (final script in scripts) {
      final log = await _logRepo.getForScript(script.id);
      rows.add(_ScriptRow(script: script, lastRun: log?.endedAt ?? log?.startedAt));
    }
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _activeScriptId = activeId;
      _loading = false;
    });
  }

  Future<void> _setActive(String scriptId, bool active) async {
    // ignore: avoid_print
    print('[ScriptsTab] _setActive: scriptId=$scriptId active=$active (current activeId=$_activeScriptId)');
    if (active) {
      await _scriptRepo.setActiveScriptId(scriptId);
    } else if (_activeScriptId == scriptId) {
      await _scriptRepo.clearActiveScript();
    }
    await OverlayService.broadcastActiveScript();
    await _load();
    widget.onChanged();
  }

  Future<void> _confirmDelete(Script script) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete script?'),
        content: Text(
          'Delete "${script.name}"? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    await _logRepo.deleteForScript(script.id);
    await _scriptRepo.delete(script.id);
    await OverlayService.broadcastActiveScript();
    await _load();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_rows.isEmpty) {
      return Center(
        child: Text(
          'No scripts yet.\nTap + to create one.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      );
    }

    final dateFmt = DateFormat.yMMMd().add_jm();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final row = _rows[index];
          final script = row.script;
          final isActive = script.id == _activeScriptId;

          return Card(
            color: isActive
                ? Theme.of(context).colorScheme.primaryContainer.withValues(
                      alpha: 0.35,
                    )
                : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Switch(
                    value: isActive,
                    onChanged: (v) => _setActive(script.id, v),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          script.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '${script.steps.length} steps'
                          '${isActive ? ' · Active' : ''}'
                          '${row.lastRun != null ? ' · Last run ${dateFmt.format(row.lastRun!)}' : ''}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: 'Delete',
                    onPressed: () => _confirmDelete(script),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit),
                    tooltip: 'Edit',
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ScriptEditorScreen.edit(
                            scriptId: script.id,
                          ),
                        ),
                      );
                      await _load();
                      widget.onChanged();
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ScriptRow {
  const _ScriptRow({required this.script, this.lastRun});

  final Script script;
  final DateTime? lastRun;
}
