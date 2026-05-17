import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Android display size in physical pixels (matches [GestureDescription] coords).
class ScreenMetrics {
  const ScreenMetrics({
    required this.widthPx,
    required this.heightPx,
    required this.density,
  });

  final double widthPx;
  final double heightPx;
  final double density;

  factory ScreenMetrics.fromMap(Map<dynamic, dynamic> map) => ScreenMetrics(
        widthPx: (map['widthPx'] as num).toDouble(),
        heightPx: (map['heightPx'] as num).toDouble(),
        density: (map['density'] as num).toDouble(),
      );
}

/// Maps between overlay-local layout coords and full-screen physical pixels.
///
/// Uses [RenderBox.localToGlobal] so taps match gestures even when the overlay
/// window is offset (e.g. status bar) or sized differently than the display.
class ScreenCoordinateMapper {
  ScreenCoordinateMapper(this.metrics);

  final ScreenMetrics metrics;

  double get density => metrics.density;

  Offset screenLogicalToPhysical(Offset screenLogical) => Offset(
        screenLogical.dx * density,
        screenLogical.dy * density,
      );

  Offset physicalToScreenLogical(double x, double y) => Offset(
        x / density,
        y / density,
      );

  Offset physicalToOverlayLocal(RenderBox overlayBox, double x, double y) {
    final screenLogical = physicalToScreenLogical(x, y);
    return overlayBox.globalToLocal(screenLogical);
  }

  Offset overlayLocalToPhysical(RenderBox overlayBox, Offset local) {
    final screenLogical = overlayBox.localToGlobal(local);
    return screenLogicalToPhysical(screenLogical);
  }

  Offset overlayDeltaToPhysical(Offset logicalDelta) => Offset(
        logicalDelta.dx * density,
        logicalDelta.dy * density,
      );

}
