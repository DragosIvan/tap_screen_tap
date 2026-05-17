import 'tap_step.dart';

enum RunModeType { untilStopped, iterations }

class RunMode {
  const RunMode.untilStopped() : type = RunModeType.untilStopped, count = 1;

  const RunMode.iterations(this.count) : type = RunModeType.iterations;

  final RunModeType type;
  final int count;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'count': count,
      };

  factory RunMode.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? RunModeType.untilStopped.name;
    final count = json['count'] as int? ?? 1;
    if (typeName == RunModeType.iterations.name) {
      return RunMode.iterations(count);
    }
    return const RunMode.untilStopped();
  }
}

class Script {
  const Script({
    required this.id,
    required this.name,
    required this.steps,
    this.tapRandomnessEnabled = false,
    this.globalRadiusPx = 15,
    this.defaultMinDelayMs = 1000,
    this.defaultMaxDelayMs = 3000,
    this.globalRandomDelayEnabled = false,
    this.globalMaxRandomDelaySec = 3,
    this.endDelayMs = 0,
    this.runMode = const RunMode.untilStopped(),
  });

  final String id;
  final String name;
  final List<TapStep> steps;
  final bool tapRandomnessEnabled;
  final int globalRadiusPx;
  final int defaultMinDelayMs;
  final int defaultMaxDelayMs;
  final bool globalRandomDelayEnabled;
  final int globalMaxRandomDelaySec;
  final int endDelayMs;
  final RunMode runMode;

  Script copyWith({
    String? id,
    String? name,
    List<TapStep>? steps,
    bool? tapRandomnessEnabled,
    int? globalRadiusPx,
    int? defaultMinDelayMs,
    int? defaultMaxDelayMs,
    bool? globalRandomDelayEnabled,
    int? globalMaxRandomDelaySec,
    int? endDelayMs,
    RunMode? runMode,
  }) {
    return Script(
      id: id ?? this.id,
      name: name ?? this.name,
      steps: steps ?? this.steps,
      tapRandomnessEnabled: tapRandomnessEnabled ?? this.tapRandomnessEnabled,
      globalRadiusPx: globalRadiusPx ?? this.globalRadiusPx,
      defaultMinDelayMs: defaultMinDelayMs ?? this.defaultMinDelayMs,
      defaultMaxDelayMs: defaultMaxDelayMs ?? this.defaultMaxDelayMs,
      globalRandomDelayEnabled:
          globalRandomDelayEnabled ?? this.globalRandomDelayEnabled,
      globalMaxRandomDelaySec:
          globalMaxRandomDelaySec ?? this.globalMaxRandomDelaySec,
      endDelayMs: endDelayMs ?? this.endDelayMs,
      runMode: runMode ?? this.runMode,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'steps': steps.map((s) => s.toJson()).toList(),
        'tapRandomnessEnabled': tapRandomnessEnabled,
        'globalRadiusPx': globalRadiusPx,
        'defaultMinDelayMs': defaultMinDelayMs,
        'defaultMaxDelayMs': defaultMaxDelayMs,
        'globalRandomDelayEnabled': globalRandomDelayEnabled,
        'globalMaxRandomDelaySec': globalMaxRandomDelaySec,
        'endDelayMs': endDelayMs,
        'runMode': runMode.toJson(),
      };

  /// Map sent to Kotlin MethodChannel.
  Map<String, dynamic> toEngineMap() => {
        'id': id,
        'name': name,
        'steps': steps.map((s) => s.toJson()).toList(),
        'tapRandomnessEnabled': tapRandomnessEnabled,
        'globalRadiusPx': globalRadiusPx,
        'defaultMinDelayMs': defaultMinDelayMs,
        'defaultMaxDelayMs': defaultMaxDelayMs,
        'globalRandomDelayEnabled': globalRandomDelayEnabled,
        'globalMaxRandomDelaySec': globalMaxRandomDelaySec,
        'endDelayMs': endDelayMs,
      };

  factory Script.fromJson(Map<String, dynamic> json) => Script(
        id: json['id'] as String,
        name: json['name'] as String,
        steps: (json['steps'] as List<dynamic>)
            .map((e) => TapStep.fromJson(e as Map<String, dynamic>))
            .toList(),
        tapRandomnessEnabled: json['tapRandomnessEnabled'] as bool? ?? false,
        globalRadiusPx: json['globalRadiusPx'] as int? ?? 15,
        defaultMinDelayMs: json['defaultMinDelayMs'] as int? ?? 1000,
        defaultMaxDelayMs: json['defaultMaxDelayMs'] as int? ?? 3000,
        globalRandomDelayEnabled:
            json['globalRandomDelayEnabled'] as bool? ?? false,
        globalMaxRandomDelaySec: json['globalMaxRandomDelaySec'] as int? ?? 3,
        endDelayMs: json['endDelayMs'] as int? ?? 0,
        runMode: json['runMode'] != null
            ? RunMode.fromJson(json['runMode'] as Map<String, dynamic>)
            : const RunMode.untilStopped(),
      );

  factory Script.empty({required String id, String name = 'New Script'}) =>
      Script(id: id, name: name, steps: const []);
}
