import 'dart:math' as math;
import 'dart:typed_data';

import 'luma_frame.dart';
import 'norm_rect.dart';

/// A puck-shaped dark blob, in normalized frame coordinates.
class PuckBlob {
  const PuckBlob({
    required this.x,
    required this.y,
    required this.area,
    required this.width,
    required this.height,
  });

  final double x;
  final double y;

  /// Size in analysis-grid cells.
  final int area;

  /// Bounding-box size in analysis-grid cells.
  final int width;
  final int height;
}

class PuckFinderConfig {
  const PuckFinderConfig({
    // A black puck on a white/grey shooting pad reads well under half the
    // pad's brightness; stick tape, shadows and skates are the usual
    // look-alikes and are mostly rejected by the size/shape checks below.
    this.darkRatio = 0.55,
    this.minAreaFactor = 0.3,
    this.maxAreaFactor = 3.0,
    // Blob cells / bounding-box cells. A disc is ~0.79; a thin stick blade
    // or shaft is much lower.
    this.minFill = 0.35,
    // A puck seen from a low side angle is an ellipse, so allow some
    // stretch, but not a stick's length.
    this.maxAspect = 3.5,
  });

  final double darkRatio;
  final double minAreaFactor;
  final double maxAreaFactor;
  final double minFill;
  final double maxAspect;
}

/// Outputs: [rect]'s cell bounds on [frame] as (x0, y0, x1, y1), inclusive.
(int, int, int, int) _cellBounds(LumaFrame frame, NormRect rect) {
  final x0 = (rect.left * frame.width).floor().clamp(0, frame.width - 1);
  final y0 = (rect.top * frame.height).floor().clamp(0, frame.height - 1);
  final x1 = (rect.right * frame.width).ceil().clamp(0, frame.width - 1);
  final y1 = (rect.bottom * frame.height).ceil().clamp(0, frame.height - 1);
  return (x0, y0, x1, y1);
}

/// Outputs: the median luma inside [rect] -- the shooting pad's brightness
/// when [rect] is the shooting zone, which the puck's darkness is judged
/// against so detection follows lighting changes.
int medianLuma(LumaFrame frame, NormRect rect) {
  final (x0, y0, x1, y1) = _cellBounds(frame, rect);
  final histogram = List<int>.filled(256, 0);
  var count = 0;
  for (var y = y0; y <= y1; y++) {
    for (var x = x0; x <= x1; x++) {
      histogram[frame.at(x, y)]++;
      count++;
    }
  }
  var seen = 0;
  for (var v = 0; v < 256; v++) {
    seen += histogram[v];
    if (seen * 2 >= count) return v;
  }
  return 255;
}

/// Outputs: the expected puck area in grid cells on [frame] for a puck
/// that looks [width] x [height] (both fractions of frame width) -- an
/// ellipse, since the camera sees the flat puck at an angle.
double expectedPuckArea(LumaFrame frame, double width, double height) =>
    math.pi / 4 * (width * frame.width) * (height * frame.width);

/// Finds puck-like blobs inside [region]: connected cells darker than
/// [referenceLuma] x [PuckFinderConfig.darkRatio] whose size is near
/// [expectedArea] and whose shape is compact.
///
/// Outputs: every passing blob, unordered.
List<PuckBlob> findPuckBlobs(
  LumaFrame frame,
  NormRect region, {
  required int referenceLuma,
  required double expectedArea,
  PuckFinderConfig config = const PuckFinderConfig(),
}) {
  final (x0, y0, x1, y1) = _cellBounds(frame, region);
  final w = x1 - x0 + 1;
  final h = y1 - y0 + 1;
  final threshold = referenceLuma * config.darkRatio;
  final minArea = math.max(2, (expectedArea * config.minAreaFactor).floor());
  final maxArea = math.max(minArea, (expectedArea * config.maxAreaFactor).ceil());

  final visited = Uint8List(w * h);
  final stack = <int>[];
  final blobs = <PuckBlob>[];

  for (var sy = 0; sy < h; sy++) {
    for (var sx = 0; sx < w; sx++) {
      final seed = sy * w + sx;
      if (visited[seed] != 0) continue;
      visited[seed] = 1;
      if (frame.at(x0 + sx, y0 + sy) >= threshold) continue;

      var area = 0;
      var sumX = 0;
      var sumY = 0;
      var minX = sx, maxX = sx, minY = sy, maxY = sy;
      stack.add(seed);
      while (stack.isNotEmpty) {
        final i = stack.removeLast();
        final cx = i % w;
        final cy = i ~/ w;
        area++;
        sumX += cx;
        sumY += cy;
        if (cx < minX) minX = cx;
        if (cx > maxX) maxX = cx;
        if (cy < minY) minY = cy;
        if (cy > maxY) maxY = cy;
        for (final (nx, ny) in [(cx - 1, cy), (cx + 1, cy), (cx, cy - 1), (cx, cy + 1)]) {
          if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
          final n = ny * w + nx;
          if (visited[n] != 0) continue;
          visited[n] = 1;
          if (frame.at(x0 + nx, y0 + ny) < threshold) stack.add(n);
        }
      }

      if (area < minArea || area > maxArea) continue;
      final boxW = maxX - minX + 1;
      final boxH = maxY - minY + 1;
      if (area / (boxW * boxH) < config.minFill) continue;
      if (math.max(boxW, boxH) / math.min(boxW, boxH) > config.maxAspect) continue;

      blobs.add(PuckBlob(
        x: (x0 + sumX / area + 0.5) / frame.width,
        y: (y0 + sumY / area + 0.5) / frame.height,
        area: area,
        width: boxW,
        height: boxH,
      ));
    }
  }
  return blobs;
}

/// A resting puck measured for calibration, in normalized frame
/// coordinates; [width]/[height] are fractions of frame width.
class PuckMeasurement {
  const PuckMeasurement({required this.x, required this.y, required this.width, required this.height});

  final double x;
  final double y;
  final double width;
  final double height;
}

/// Measures a resting puck for calibration: the largest puck-like blob in
/// [zone], searched with loose size limits around a disc [guessWidth] wide.
///
/// Outputs: its centre and on-screen size, or `null` if no puck is visible.
PuckMeasurement? measurePuck(LumaFrame frame, NormRect zone, {required double guessWidth}) {
  final blobs = findPuckBlobs(
    frame,
    zone,
    referenceLuma: medianLuma(frame, zone),
    expectedArea: expectedPuckArea(frame, guessWidth, guessWidth * 0.6),
    // Loose: the guess comes from the zone size and can be well off.
    config: const PuckFinderConfig(minAreaFactor: 0.1, maxAreaFactor: 8),
  );
  if (blobs.isEmpty) return null;
  final biggest = blobs.reduce((a, b) => a.area >= b.area ? a : b);
  return PuckMeasurement(
    x: biggest.x,
    y: biggest.y,
    width: biggest.width / frame.width,
    height: biggest.height / frame.width,
  );
}
