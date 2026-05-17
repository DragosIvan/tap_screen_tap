import 'log_entry.dart';

class ExecutionLog {
  const ExecutionLog({
    required this.scriptId,
    required this.scriptName,
    required this.startedAt,
    this.endedAt,
    required this.stopReason,
    required this.iterationsRequested,
    required this.iterationsCompleted,
    required this.entries,
  });

  final String scriptId;
  final String scriptName;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String stopReason;
  final int iterationsRequested;
  final int iterationsCompleted;
  final List<LogEntry> entries;

  ExecutionLog copyWith({
    DateTime? endedAt,
    String? stopReason,
    int? iterationsCompleted,
    List<LogEntry>? entries,
  }) {
    return ExecutionLog(
      scriptId: scriptId,
      scriptName: scriptName,
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      stopReason: stopReason ?? this.stopReason,
      iterationsRequested: iterationsRequested,
      iterationsCompleted: iterationsCompleted ?? this.iterationsCompleted,
      entries: entries ?? this.entries,
    );
  }

  Map<String, dynamic> toJson() => {
        'scriptId': scriptId,
        'scriptName': scriptName,
        'startedAt': startedAt.toIso8601String(),
        'endedAt': endedAt?.toIso8601String(),
        'stopReason': stopReason,
        'iterationsRequested': iterationsRequested,
        'iterationsCompleted': iterationsCompleted,
        'entries': entries.map((e) => e.toJson()).toList(),
      };

  factory ExecutionLog.fromJson(Map<String, dynamic> json) => ExecutionLog(
        scriptId: json['scriptId'] as String,
        scriptName: json['scriptName'] as String,
        startedAt: DateTime.parse(json['startedAt'] as String),
        endedAt: json['endedAt'] != null
            ? DateTime.parse(json['endedAt'] as String)
            : null,
        stopReason: json['stopReason'] as String? ?? 'unknown',
        iterationsRequested: json['iterationsRequested'] as int? ?? -1,
        iterationsCompleted: json['iterationsCompleted'] as int? ?? 0,
        entries: (json['entries'] as List<dynamic>)
            .map((e) => LogEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
