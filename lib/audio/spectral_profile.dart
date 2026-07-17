import 'dart:math' as math;
import 'dart:typed_data';

import 'audio_constants.dart';

/// Center frequencies (Hz) of the bands used for the spectral shape profile.
/// Spans the impulsive, broadband "crack" of a stick-puck impact at 16kHz
/// sample rate (Nyquist 8kHz).
const List<double> spectralBandCenters = [500, 1000, 2000, 3000, 4000, 6000];

/// Placeholder reference profile for a stick-on-puck impact's frequency
/// shape (normalized relative energy per band in [spectralBandCenters]),
/// hand-picked to bias toward the broadband high-frequency "crack" of a
/// stick/puck impact rather than the low-frequency-heavy voice/thud sounds
/// it must be distinguished from. Replaced by a real per-user calibrated
/// profile in ticket 03.
const List<double> defaultShotSpectralProfile = [0.05, 0.10, 0.20, 0.25, 0.25, 0.15];

/// Computes a normalized per-band energy "shape" profile of a PCM16 buffer
/// via the Goertzel algorithm, one energy value per entry in
/// [spectralBandCenters].
///
/// Inputs: [pcm16Bytes] raw PCM16 audio bytes; [sampleRate] the capture
/// sample rate (Hz).
/// Outputs: a [spectralBandCenters]-length list of relative band energies
/// summing to 1.0 (all zero if the input is silent/too short).
List<double> computeSpectralProfile(Uint8List pcm16Bytes, {int sampleRate = micSampleRate}) {
  final sampleCount = pcm16Bytes.length ~/ 2;
  if (sampleCount == 0) return List.filled(spectralBandCenters.length, 0.0);

  final byteData = ByteData.sublistView(pcm16Bytes, 0, sampleCount * 2);
  final samples = List<double>.generate(
    sampleCount,
    (i) => byteData.getInt16(i * 2, Endian.little) / 32768.0,
  );

  final energies = spectralBandCenters
      .map((freq) => _goertzelEnergy(samples, sampleRate, freq))
      .toList();

  final total = energies.fold<double>(0.0, (sum, e) => sum + e);
  if (total <= 0) return List.filled(spectralBandCenters.length, 0.0);
  return energies.map((e) => e / total).toList();
}

/// Single-frequency energy via the Goertzel algorithm — cheaper than a full
/// FFT when only a handful of target frequencies are needed.
double _goertzelEnergy(List<double> samples, int sampleRate, double targetFreq) {
  final n = samples.length;
  final k = (0.5 + n * targetFreq / sampleRate).floor();
  final omega = (2 * math.pi * k) / n;
  final coeff = 2 * math.cos(omega);

  var s1 = 0.0;
  var s2 = 0.0;
  for (final sample in samples) {
    final s0 = sample + coeff * s1 - s2;
    s2 = s1;
    s1 = s0;
  }
  final energy = s1 * s1 + s2 * s2 - coeff * s1 * s2;
  return energy < 0 ? 0.0 : energy;
}

/// Cosine similarity between two equal-length vectors, in [0.0, 1.0] for the
/// non-negative energy profiles this is used with. Returns 0.0 rather than
/// dividing by zero if either vector is all-zero.
double cosineSimilarity(List<double> a, List<double> b) {
  assert(a.length == b.length);
  var dot = 0.0;
  var normA = 0.0;
  var normB = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA == 0 || normB == 0) return 0.0;
  return dot / (math.sqrt(normA) * math.sqrt(normB));
}
