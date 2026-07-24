import 'dart:math' as math;
import 'dart:typed_data';

import 'audio_constants.dart';
import 'pcm16.dart';

/// Center frequencies (Hz) of the bands used for the spectral shape profile.
/// Spans the impulsive, broadband "crack" of a stick-puck impact at 16kHz
/// sample rate (Nyquist 8kHz).
const List<double> spectralBandCenters = [500, 1000, 2000, 3000, 4000, 6000];

/// Computes a normalized per-band energy "shape" profile of a PCM16 buffer
/// via the Goertzel algorithm, one energy value per entry in
/// [spectralBandCenters].
///
/// Inputs: [pcm16Bytes] raw PCM16 audio bytes; [sampleRate] the capture
/// sample rate (Hz).
/// Outputs: a [spectralBandCenters]-length list of relative band energies
/// summing to 1.0 (all zero if the input is silent/too short).
List<double> computeSpectralProfile(Uint8List pcm16Bytes, {int sampleRate = micSampleRate}) =>
    computeSpectralProfileFromSamples(decodePcm16(pcm16Bytes), sampleRate: sampleRate);

/// Same as [computeSpectralProfile], for pre-decoded samples.
///
/// Inputs: [samples] signed 16-bit PCM samples, e.g. from [decodePcm16];
/// [sampleRate] the capture sample rate (Hz).
/// Outputs: a [spectralBandCenters]-length list of relative band energies
/// summing to 1.0 (all zero if the input is silent/too short).
List<double> computeSpectralProfileFromSamples(List<int> samples, {int sampleRate = micSampleRate}) {
  if (samples.isEmpty) return List.filled(spectralBandCenters.length, 0.0);

  final normalized = List<double>.generate(samples.length, (i) => samples[i] / 32768.0);

  final energies = spectralBandCenters
      .map((freq) => _goertzelEnergy(normalized, sampleRate, freq))
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
