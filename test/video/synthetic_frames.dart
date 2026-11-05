import 'dart:typed_data';

import 'package:hockey_shot_tracker/video/luma_frame.dart';
import 'package:hockey_shot_tracker/video/norm_rect.dart';
import 'package:hockey_shot_tracker/video/video_calibration.dart';

const int frameW = 192;
const int frameH = 108;

/// A camera placement used across the video tests: shooting zone low in the
/// frame, net high, puck ~6 cells across.
const testCalibration = VideoCalibration(
  shootingZone: NormRect(0.35, 0.6, 0.65, 0.9),
  net: NormRect(0.4, 0.1, 0.6, 0.35),
  puckDiameter: 0.03,
  shotDistanceFeet: 15,
);

/// Builds a [frameW] x [frameH] frame of a light pad, with optional dark
/// discs ([discs] as normalized centre + diameter) and dark rectangles.
LumaFrame syntheticFrame({
  int background = 200,
  List<(double, double, double)> discs = const [],
  List<NormRect> darkRects = const [],
  int dark = 20,
}) {
  final pixels = Uint8List(frameW * frameH)..fillRange(0, frameW * frameH, background);
  for (final (cx, cy, d) in discs) {
    final r = d * frameW / 2;
    final px = cx * frameW;
    final py = cy * frameH;
    for (var y = 0; y < frameH; y++) {
      for (var x = 0; x < frameW; x++) {
        final dx = x + 0.5 - px;
        final dy = y + 0.5 - py;
        if (dx * dx + dy * dy <= r * r) pixels[y * frameW + x] = dark;
      }
    }
  }
  for (final rect in darkRects) {
    for (var y = (rect.top * frameH).floor(); y < (rect.bottom * frameH).ceil(); y++) {
      for (var x = (rect.left * frameW).floor(); x < (rect.right * frameW).ceil(); x++) {
        pixels[y * frameW + x] = dark;
      }
    }
  }
  return LumaFrame(width: frameW, height: frameH, pixels: pixels);
}
