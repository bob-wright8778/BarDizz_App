import 'dart:math' as math;

import 'norm_rect.dart';
import 'puck_finder.dart';

/// Regulation net opening height (crossbar to ice). Height, not the 6 ft
/// width, is what gets measured: posts are vertical, so a camera off to the
/// side still sees the full height, while the width shrinks with the angle.
const double netOpeningHeightFeet = 4;

/// Regulation puck diameter.
const double puckDiameterFeet = 0.25;

/// Field of view across the long side of a typical phone main camera (a
/// ~26 mm-equivalent lens). Flutter's camera plugin doesn't report the real
/// value, so this is an assumption -- the main source of estimate error,
/// roughly +/-15% across phones, and why the distance can be set by hand.
const double assumedLongSideFovDegrees = 69;

/// Estimates the distance from the shooting spot to the net from how big a
/// regulation net and puck look.
///
/// A pinhole camera puts anything of known real size at a depth of
/// `realSize x focalLength / sizeOnScreen`. That places the net's base
/// (from its on-screen height) and the puck (from its on-screen width, which
/// isn't foreshortened when the puck lies flat) in 3D, and the answer is the
/// gap between them.
///
/// Inputs: the marked [net] opening, the [puck] measured at the shooting
/// spot, and the upright frame's [aspect] (width / height).
/// Outputs: feet, or `null` if the result is implausible for a shooting
/// setup (likely a mis-drawn box).
double? estimateShotDistanceFeet({
  required NormRect net,
  required PuckMeasurement puck,
  required double aspect,
  double longSideFovDegrees = assumedLongSideFovDegrees,
}) {
  if (net.height <= 0 || puck.width <= 0) return null;

  // Work in units of frame width; the frame is 1 / aspect tall.
  final height = 1 / aspect;
  final longSide = math.max(1.0, height);
  final focal = (longSide / 2) / math.tan(longSideFovDegrees / 2 * math.pi / 180);

  (double, double, double) place(double nx, double ny, double depth) => (
        (nx - 0.5) * depth / focal,
        (ny - 0.5) * height * depth / focal,
        depth,
      );

  final netDepth = netOpeningHeightFeet * focal / (net.height * height);
  final puckDepth = puckDiameterFeet * focal / puck.width;
  // The middle of the net's base: where a shot crosses the goal line, at
  // ice level like the puck.
  final (nx, ny, nz) = place((net.left + net.right) / 2, net.bottom, netDepth);
  final (px, py, pz) = place(puck.x, puck.y, puckDepth);
  final feet = math.sqrt(math.pow(nx - px, 2) + math.pow(ny - py, 2) + math.pow(nz - pz, 2));

  if (feet < 3 || feet > 80) return null;
  return feet;
}
