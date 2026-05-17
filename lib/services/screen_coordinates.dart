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

  bool looksLikeLegacyOverlayLogical(
    Iterable<Offset> points,
    Size overlayLogicalSize,
  ) {
    if (points.isEmpty || overlayLogicalSize.isEmpty) return false;
    final maxX = points.map((p) => p.dx).reduce((a, b) => a > b ? a : b);
    final maxY = points.map((p) => p.dy).reduce((a, b) => a > b ? a : b);
    return maxX <= overlayLogicalSize.width * 1.05 &&
        maxY <= overlayLogicalSize.height * 1.05 &&
        maxX < metrics.widthPx * 0.6;
  }

  Offset upgradeLegacy(Offset overlayLogical, Size overlaySize) {
    final scaleX =
        overlaySize.width > 0 ? metrics.widthPx / overlaySize.width : density;
    final scaleY =
        overlaySize.height > 0 ? metrics.heightPx / overlaySize.height : density;
    return Offset(overlayLogical.dx * scaleX, overlayLogical.dy * scaleY);
  }
}
