class TapStep {
  const TapStep({
    required this.x,
    required this.y,
    this.delayAfterMs,
    this.radiusPx,
  });

  final double x;
  final double y;
  final int? delayAfterMs;
  final int? radiusPx;

  TapStep copyWith({
    double? x,
    double? y,
    int? delayAfterMs,
    int? radiusPx,
    bool clearDelayAfterMs = false,
    bool clearRadiusPx = false,
  }) {
    return TapStep(
      x: x ?? this.x,
      y: y ?? this.y,
      delayAfterMs: clearDelayAfterMs ? null : (delayAfterMs ?? this.delayAfterMs),
      radiusPx: clearRadiusPx ? null : (radiusPx ?? this.radiusPx),
    );
  }

  Map<String, dynamic> toJson() => {
        'x': x,
        'y': y,
        if (delayAfterMs != null) 'delayAfterMs': delayAfterMs,
        if (radiusPx != null) 'radiusPx': radiusPx,
      };

  factory TapStep.fromJson(Map<String, dynamic> json) => TapStep(
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        delayAfterMs: json['delayAfterMs'] as int?,
        radiusPx: json['radiusPx'] as int?,
      );
}
