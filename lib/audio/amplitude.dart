import 'dart:math' as math;
import 'dart:typed_data';

/// Computes the normalized RMS amplitude (0.0-1.0) of a little-endian
/// signed 16-bit PCM buffer, as produced by `record`'s AudioEncoder.pcm16bits.
///
/// Inputs: [pcm16Bytes] raw PCM16 audio bytes (byte length should be even;
/// a trailing odd byte is ignored).
/// Outputs: RMS level scaled against the max int16 magnitude, clamped to
/// [0.0, 1.0]. Returns 0.0 for empty/silent input.
double computeAmplitude(Uint8List pcm16Bytes) {
  final sampleCount = pcm16Bytes.length ~/ 2;
  if (sampleCount == 0) return 0.0;

  final byteData = ByteData.sublistView(pcm16Bytes, 0, sampleCount * 2);
  var sumSquares = 0.0;
  for (var i = 0; i < sampleCount; i++) {
    final sample = byteData.getInt16(i * 2, Endian.little);
    sumSquares += sample * sample;
  }

  const maxAmplitude = 32768.0;
  final rms = math.sqrt(sumSquares / sampleCount);
  return (rms / maxAmplitude).clamp(0.0, 1.0);
}
