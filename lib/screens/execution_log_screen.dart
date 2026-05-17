import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/execution_log.dart';
import '../models/log_entry.dart';
import '../services/log_repository.dart';

class ExecutionLogScreen extends StatefulWidget {
  const ExecutionLogScreen({
    super.key,
    required this.scriptId,
    required this.scriptName,
  });

  final String scriptId;
  final String scriptName;

  @override
  State<ExecutionLogScreen> createState() => _ExecutionLogScreenState();
}

class _ExecutionLogScreenState extends State<ExecutionLogScreen> {
  final _logRepo = LogRepository();
  ExecutionLog? _log;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final log = await _logRepo.getForScript(widget.scriptId);
    if (!mounted) return;
    setState(() {
      _log = log;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.scriptName} log')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final log = _log;
    if (log == null) {
      return const Center(child: Text('No execution recorded yet'));
    }

    final timeFmt = DateFormat.Hms();
    final duration = log.endedAt != null
        ? log.endedAt!.difference(log.startedAt)
        : null;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Summary',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text('Started: ${timeFmt.format(log.startedAt)}'),
                if (log.endedAt != null)
                  Text('Ended: ${timeFmt.format(log.endedAt!)}'),
                if (duration != null)
                  Text('Duration: ${duration.inSeconds}s'),
                Text('Stop reason: ${log.stopReason}'),
                Text(
                  'Iterations: ${log.iterationsCompleted}'
                  '${log.iterationsRequested >= 0 ? ' / ${log.iterationsRequested}' : ''}',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...log.entries.map((e) => _LogEntryCard(entry: e)),
      ],
    );
  }
}

class _LogEntryCard extends StatelessWidget {
  const _LogEntryCard({required this.entry});

  final LogEntry entry;

  @override
  Widget build(BuildContext context) {
    final time = DateFormat.Hms().format(entry.timestamp);
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _titleFor(entry),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _bodyFor(entry),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              time,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _titleFor(LogEntry entry) {
    switch (entry.type) {
      case LogEntryType.runStarted:
        return 'Run started';
      case LogEntryType.iterationStarted:
        return 'Iteration ${entry.data['iteration']}';
      case LogEntryType.tapPerformed:
        return 'Step ${(entry.data['stepIndex'] as num).toInt() + 1} — Tap';
      case LogEntryType.delayApplied:
        final idx = entry.data['stepIndex'];
        if (idx == -1) return 'End delay';
        return 'Delay after step ${(idx as num).toInt() + 1}';
      case LogEntryType.iterationCompleted:
        return 'Iteration ${entry.data['iteration']} done';
      case LogEntryType.runEnded:
        return 'Run ended';
      case LogEntryType.error:
        return 'Error';
    }
  }

  String _bodyFor(LogEntry entry) {
    final d = entry.data;
    switch (entry.type) {
      case LogEntryType.runStarted:
        return '${d['stepCount']} steps, iterations: ${d['iterationsRequested']}';
      case LogEntryType.iterationStarted:
      case LogEntryType.iterationCompleted:
        return '';
      case LogEntryType.tapPerformed:
        final jitter = d['jitterApplied'] == true;
        final ax = (d['actualX'] as num).toStringAsFixed(0);
        final ay = (d['actualY'] as num).toStringAsFixed(0);
        if (jitter) {
          final dx = (d['definedX'] as num).toStringAsFixed(0);
          final dy = (d['definedY'] as num).toStringAsFixed(0);
          return 'Tapped ($ax, $ay) [jittered from ($dx, $dy), r=${d['radiusPx']}]';
        }
        return 'Tapped ($ax, $ay)';
      case LogEntryType.delayApplied:
        final total = d['totalDelayMs'];
        final base = d['baseDelayMs'];
        final random = d['randomAddonMs'];
        return 'Waited ${(total as num) / 1000}s (base ${base}ms + random ${random}ms)';
      case LogEntryType.runEnded:
        return '${d['totalTaps']} taps, ${d['totalDurationMs']}ms, ${d['stopReason']}';
      case LogEntryType.error:
        return d['message']?.toString() ?? 'Unknown error';
    }
  }
}
