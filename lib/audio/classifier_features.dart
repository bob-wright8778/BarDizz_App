import 'dart:typed_data';

import 'amplitude.dart';
import 'audio_constants.dart';
import 'pcm16.dart';
import 'spectral_profile.dart';

/// Feature names in the exact order [extractClassifierFeatures] returns them
/// -- must match the Python training-side `dart_features_lib.py`'s
/// `FEATURE_NAMES` (`tool/ml_investigation/`), since the trained model in
/// [classifierTrees] was fit on that order.
const List<String> classifierFeatureNames = [
  'goertzel_band_0',
  'goertzel_band_1',
  'goertzel_band_2',
  'goertzel_band_3',
  'goertzel_band_4',
  'goertzel_band_5',
  'amplitude',
  'zero_crossing_rate',
];

/// Fraction of adjacent-sample sign changes across [pcm16Bytes], in
/// `[0.0, 1.0]`. Zero counts as non-negative (so a 0 -> positive transition
/// is not a crossing, matching the Python-side
/// `compute_zero_crossing_rate`). Returns 0.0 for fewer than 2 samples.
double computeZeroCrossingRate(Uint8List pcm16Bytes) =>
    computeZeroCrossingRateFromSamples(decodePcm16(pcm16Bytes));

/// Same as [computeZeroCrossingRate], for pre-decoded samples.
///
/// Inputs: [samples] signed 16-bit PCM samples, e.g. from [decodePcm16].
/// Outputs: fraction of adjacent-sample sign changes, in `[0.0, 1.0]`.
/// Returns 0.0 for fewer than 2 samples.
double computeZeroCrossingRateFromSamples(List<int> samples) {
  if (samples.length < 2) return 0.0;

  var crossings = 0;
  var previousNonNegative = samples[0] >= 0;
  for (var i = 1; i < samples.length; i++) {
    final currentNonNegative = samples[i] >= 0;
    if (currentNonNegative != previousNonNegative) crossings++;
    previousNonNegative = currentNonNegative;
  }
  return crossings / (samples.length - 1);
}

/// Builds the classifier's 8-value feature vector for one PCM16 clip, in
/// [classifierFeatureNames] order. Reuses [computeSpectralProfile] and
/// [computeAmplitude] (the existing heuristic's math) rather than
/// recomputing them -- only [computeZeroCrossingRate] is new.
///
/// Inputs: [pcm16Bytes] raw PCM16 audio; [sampleRate] the capture rate.
/// Outputs: an 8-value feature vector.
List<double> extractClassifierFeatures(Uint8List pcm16Bytes, {int sampleRate = micSampleRate}) {
  final samples = decodePcm16(pcm16Bytes);
  final profile = computeSpectralProfileFromSamples(samples, sampleRate: sampleRate);
  final amplitude = computeAmplitudeFromSamples(samples);
  final zeroCrossingRate = computeZeroCrossingRateFromSamples(samples);
  return [...profile, amplitude, zeroCrossingRate];
}
