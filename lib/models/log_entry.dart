enum LogEntryType {
  runStarted,
  iterationStarted,
  tapPerformed,
  delayApplied,
  iterationCompleted,
  runEnded,
  error,
}

class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.type,
    required this.data,
  });

  final DateTime timestamp;
  final LogEntryType type;
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => {
        'timestamp': timestamp.toIso8601String(),
        'type': type.name,
        'data': data,
      };

  factory LogEntry.fromJson(Map<String, dynamic> json) => LogEntry(
        timestamp: DateTime.parse(json['timestamp'] as String),
        type: LogEntryType.values.byName(json['type'] as String),
        data: Map<String, dynamic>.from(json['data'] as Map),
      );

  factory LogEntry.fromEngineEvent(Map<String, dynamic> entry) {
    final typeName = entry['type'] as String;
    final data = Map<String, dynamic>.from(entry);
    data.remove('type');
    data.remove('timestamp');
    final ts = entry['timestamp'];
    return LogEntry(
      timestamp: ts is int
          ? DateTime.fromMillisecondsSinceEpoch(ts)
          : DateTime.now(),
      type: LogEntryType.values.byName(typeName),
      data: data,
    );
  }
}
