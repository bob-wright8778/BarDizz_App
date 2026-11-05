import 'dart:typed_data';

/// Width (in cells) of the grid every camera frame is shrunk to before
/// analysis. Fixed, so a calibration taken on one camera resolution still
/// lines up on another: everything downstream works in fractions of this
/// grid, never in raw camera pixels.
const int analysisGridWidth = 192;

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
