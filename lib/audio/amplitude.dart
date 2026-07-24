import 'dart:math' as math;
import 'dart:typed_data';

import 'pcm16.dart';

/// Computes the normalized RMS amplitude (0.0-1.0) of a little-endian
/// signed 16-bit PCM buffer, as produced by `record`'s AudioEncoder.pcm16bits.
///
/// Inputs: [pcm16Bytes] raw PCM16 audio bytes (byte length should be even;
/// a trailing odd byte is ignored).
/// Outputs: RMS level scaled against the max int16 magnitude, clamped to
/// [0.0, 1.0]. Returns 0.0 for empty/silent input.
double computeAmplitude(Uint8List pcm16Bytes) => computeAmplitudeFromSamples(decodePcm16(pcm16Bytes));

/// Same as [computeAmplitude], for pre-decoded samples.
///
/// Inputs: [samples] signed 16-bit PCM samples, e.g. from [decodePcm16].
/// Outputs: RMS level scaled against the max int16 magnitude, clamped to
/// [0.0, 1.0]. Returns 0.0 for empty/silent input.
double computeAmplitudeFromSamples(List<int> samples) {
  if (samples.isEmpty) return 0.0;

  var sumSquares = 0.0;
  for (final sample in samples) {
    sumSquares += sample * sample;
  }

  const maxAmplitude = 32768.0;
  final rms = math.sqrt(sumSquares / samples.length);
  return (rms / maxAmplitude).clamp(0.0, 1.0);
}
