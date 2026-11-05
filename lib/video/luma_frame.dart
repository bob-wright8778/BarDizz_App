import 'dart:typed_data';

/// Upper bound (in cells) on the long side of the grid every camera frame
/// is shrunk to before analysis. Everything downstream works in fractions of
/// the frame, never in raw camera pixels, so a calibration taken at one
/// resolution still lines up at another. At ~720 px camera frames this is a
/// 2x shrink, keeping a puck 12 ft away about 5 cells wide.
const int analysisGridWidth = 360;

/// One greyscale camera frame on the analysis grid: [width] x [height] luma
/// cells, row-major, 0 = black.
class LumaFrame {
  LumaFrame({required this.width, required this.height, required this.pixels})
      : assert(pixels.length == width * height);

  final int width;
  final int height;
  final Uint8List pixels;

  int at(int x, int y) => pixels[y * width + x];
}

/// Shrinks a camera luma (Y) plane onto the analysis grid by averaging
/// square blocks, which also smooths sensor noise.
///
/// Inputs: [plane] the raw Y plane, its [width]/[height] in pixels and
/// [bytesPerRow] stride (often wider than [width]), and the [targetWidth]
/// to shrink to.
/// Outputs: a [LumaFrame] at most [targetWidth] cells wide, keeping the
/// source aspect ratio.
LumaFrame downsampleLuma(
  Uint8List plane, {
  required int width,
  required int height,
  required int bytesPerRow,
  int targetWidth = analysisGridWidth,
}) {
  final block = (width / targetWidth).ceil().clamp(1, width);
  final outW = width ~/ block;
  final outH = height ~/ block;
  final out = Uint8List(outW * outH);
  final area = block * block;
  for (var oy = 0; oy < outH; oy++) {
    final rowBase = oy * block;
    for (var ox = 0; ox < outW; ox++) {
      final colBase = ox * block;
      var sum = 0;
      for (var dy = 0; dy < block; dy++) {
        final start = (rowBase + dy) * bytesPerRow + colBase;
        for (var dx = 0; dx < block; dx++) {
          sum += plane[start + dx];
        }
      }
      out[oy * outW + ox] = sum ~/ area;
    }
  }
  return LumaFrame(width: outW, height: outH, pixels: out);
}

/// Rotates [frame] clockwise by [quarterTurns] x 90 degrees -- used to turn
/// the camera sensor's fixed landscape frames upright for however the phone
/// is standing.
LumaFrame rotateLuma(LumaFrame frame, int quarterTurns) {
  final turns = quarterTurns % 4;
  if (turns == 0) return frame;
  final w = frame.width;
  final h = frame.height;
  final src = frame.pixels;
  final out = Uint8List(w * h);
  final outW = turns == 2 ? w : h;
  final outH = turns == 2 ? h : w;
  // Per-turn loops rather than one loop with a per-pixel switch: this runs on
  // every camera frame.
  for (var y = 0; y < h; y++) {
    final row = y * w;
    if (turns == 1) {
      for (var x = 0; x < w; x++) {
        out[x * outW + (h - 1 - y)] = src[row + x];
      }
    } else if (turns == 2) {
      for (var x = 0; x < w; x++) {
        out[(h - 1 - y) * outW + (w - 1 - x)] = src[row + x];
      }
    } else {
      for (var x = 0; x < w; x++) {
        out[(w - 1 - x) * outW + y] = src[row + x];
      }
    }
  }
  return LumaFrame(width: outW, height: outH, pixels: out);
}
