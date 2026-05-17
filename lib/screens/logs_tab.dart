import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/script.dart';
import '../services/log_repository.dart';
import '../services/script_repository.dart';
import 'execution_log_screen.dart';

class LogsTab extends StatefulWidget {
  const LogsTab({super.key});

  @override
  State<LogsTab> createState() => _LogsTabState();
}

class _LogsTabState extends State<LogsTab> {
  final _scriptRepo = ScriptRepository();
  final _logRepo = LogRepository();
  List<Script> _scripts = [];
  final Map<String, DateTime?> _lastRuns = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final scripts = await _scriptRepo.getAll();
    final runs = <String, DateTime?>{};
    for (final s in scripts) {
      final log = await _logRepo.getForScript(s.id);
      runs[s.id] = log?.endedAt ?? log?.startedAt;
    }
    if (!mounted) return;
    setState(() {
      _scripts = scripts;
      _lastRuns.addAll(runs);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_scripts.isEmpty) {
      return const Center(child: Text('No scripts yet'));
    }

    final dateFmt = DateFormat.yMMMd().add_jm();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemCount: _scripts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final script = _scripts[index];
          final lastRun = _lastRuns[script.id];
          return Card(
            child: ListTile(
              title: Text(script.name),
              subtitle: Text(
                lastRun != null
                    ? 'Last run: ${dateFmt.format(lastRun)}'
                    : 'No runs yet',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ExecutionLogScreen(
                      scriptId: script.id,
                      scriptName: script.name,
                    ),
                  ),
                );
                await _load();
              },
            ),
          );
        },
      ),
    );
  }
}
