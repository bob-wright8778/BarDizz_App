import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/video/distance_estimate.dart';
import 'package:hockey_shot_tracker/video/norm_rect.dart';
import 'package:hockey_shot_tracker/video/puck_finder.dart';

/// A pinhole camera with the assumed field of view, looking level, so tests
/// can place a real net and puck in feet and see where they'd land on
/// screen.
class _Camera {
  _Camera({required this.aspect});

  final double aspect; // width / height
  static const double heightFeet = 3; // lens above the ice

  double get _h => 1 / aspect;
  double get _focal =>
      (math.max(1.0, _h) / 2) / math.tan(assumedLongSideFovDegrees / 2 * math.pi / 180);

  /// Inputs: a point [x] ft right of the lens, [up] ft above the ice, [z] ft ahead.
  /// Outputs: normalized screen position.
  (double, double) project(double x, double up, double z) {
    final down = heightFeet - up;
    return (0.5 + x * _focal / z, 0.5 + down * _focal / z / _h);
  }

  NormRect netAt(double x, double z) {
    final (l, top) = project(x - 3, 4, z);
    final (r, bottom) = project(x + 3, 0, z);
    return NormRect(l, top, r, bottom);
  }

  PuckMeasurement puckAt(double x, double z) {
    final (px, py) = project(x, 0, z);
    return PuckMeasurement(x: px, y: py, width: puckDiameterFeet * _focal / z, height: 0.01);
  }
}

void main() {
  test('phone upright behind the shooter: recovers the real distance', () {
    final cam = _Camera(aspect: 3 / 4);
    final feet = estimateShotDistanceFeet(
      net: cam.netAt(0, 23),
      puck: cam.puckAt(0, 8),
      aspect: 3 / 4,
    );
    expect(feet, closeTo(15, 0.01));
  });

  test('phone sideways beside the shooter: recovers the real distance', () {
    final cam = _Camera(aspect: 4 / 3);
    final feet = estimateShotDistanceFeet(
      net: cam.netAt(-4, 26),
      puck: cam.puckAt(-3, 6),
      aspect: 4 / 3,
    );
    // sqrt(1^2 + 20^2)
    expect(feet, closeTo(20.02, 0.01));
  });

  test('a net seen at an angle still works: only its height is used', () {
    final cam = _Camera(aspect: 3 / 4);
    final square = cam.netAt(0, 23);
    // Same posts and crossbar, but the opening looks half as wide.
    final angled = NormRect(square.left, square.top, square.left + square.width / 2, square.bottom);
    final feet = estimateShotDistanceFeet(net: angled, puck: cam.puckAt(0, 8), aspect: 3 / 4);
    expect(feet, closeTo(15, 1.5));
  });

  test('a puck measured 10% too small shifts the answer modestly, not wildly', () {
    final cam = _Camera(aspect: 3 / 4);
    final p = cam.puckAt(0, 8);
    final off = PuckMeasurement(x: p.x, y: p.y, width: p.width * 0.9, height: p.height);
    final feet = estimateShotDistanceFeet(net: cam.netAt(0, 23), puck: off, aspect: 3 / 4)!;
    expect(feet, inInclusiveRange(13, 15));
  });

  test('returns null for an impossible setup, like a box drawn around a tiny net', () {
    final cam = _Camera(aspect: 3 / 4);
    final feet = estimateShotDistanceFeet(
      net: const NormRect(0.49, 0.49, 0.5, 0.495),
      puck: cam.puckAt(0, 8),
      aspect: 3 / 4,
    );
    expect(feet, isNull);
  });
}
