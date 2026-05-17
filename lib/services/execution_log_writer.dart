import 'dart:async';

import '../models/execution_log.dart';
import '../models/log_entry.dart';
import 'clicker_channel.dart';
import 'log_repository.dart';
import 'settings_repository.dart';

class ExecutionLogWriter {
  ExecutionLogWriter(this._logRepository);

  final LogRepository _logRepository;
  final _settings = SettingsRepository();
  ExecutionLog? _current;
  // Cached per-run: read once at runStarted so the setting can be changed
  // between runs without affecting an in-progress execution.
  bool _loggingEnabledForRun = false;
  StreamSubscription<Map<dynamic, dynamic>>? _subscription;

  void startListening() {
    _subscription ??= ClickerChannel.eventStream.listen(_onEvent);
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _onEvent(Map<dynamic, dynamic> event) async {
    final eventName = event['event'] as String?;
    if (eventName != 'logEvent') return;

    final scriptId = event['scriptId'] as String;
    final entryMap = Map<String, dynamic>.from(event['entry'] as Map);
    final entry = LogEntry.fromEngineEvent(entryMap);

    if (entry.type == LogEntryType.runStarted) {
      // Snapshot the setting at run start so it stays stable for this run.
      _loggingEnabledForRun = await _settings.isLoggingEnabled();
      if (!_loggingEnabledForRun) return;

      _current = ExecutionLog(
        scriptId: scriptId,
        scriptName: entry.data['scriptName'] as String? ?? 'Script',
        startedAt: entry.timestamp,
        stopReason: 'running',
        iterationsRequested:
            (entry.data['iterationsRequested'] as num?)?.toInt() ?? -1,
        iterationsCompleted: 0,
        entries: [entry],
      );
      return;
    }

    if (!_loggingEnabledForRun) return;
    if (_current == null || _current!.scriptId != scriptId) return;

    final entries = [..._current!.entries, entry];
    var log = _current!.copyWith(entries: entries);

    if (entry.type == LogEntryType.runEnded) {
      log = log.copyWith(
        endedAt: entry.timestamp,
        stopReason: entry.data['stopReason'] as String? ?? 'unknown',
        iterationsCompleted:
            (entry.data['iterationsCompleted'] as num?)?.toInt() ?? 0,
      );
      await _logRepository.save(log);
      _current = null;
      return;
    }

    if (entry.type == LogEntryType.error) {
      log = log.copyWith(
        endedAt: entry.timestamp,
        stopReason: 'error',
      );
      await _logRepository.save(log);
      _current = null;
      return;
    }

    _current = log;
  }
}
