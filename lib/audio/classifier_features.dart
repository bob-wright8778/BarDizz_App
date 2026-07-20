import 'dart:typed_data';

import 'amplitude.dart';
import 'audio_constants.dart';
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
double computeZeroCrossingRate(Uint8List pcm16Bytes) {
  final sampleCount = pcm16Bytes.length ~/ 2;
  if (sampleCount < 2) return 0.0;

  final byteData = ByteData.sublistView(pcm16Bytes, 0, sampleCount * 2);
  var crossings = 0;
  var previousNonNegative = byteData.getInt16(0, Endian.little) >= 0;
  for (var i = 1; i < sampleCount; i++) {
    final currentNonNegative = byteData.getInt16(i * 2, Endian.little) >= 0;
    if (currentNonNegative != previousNonNegative) crossings++;
    previousNonNegative = currentNonNegative;
  }
  return crossings / (sampleCount - 1);
}

/// Builds the classifier's 8-value feature vector for one PCM16 clip, in
/// [classifierFeatureNames] order. Reuses [computeSpectralProfile] and
/// [computeAmplitude] (the existing heuristic's math) rather than
/// recomputing them -- only [computeZeroCrossingRate] is new.
///
/// Inputs: [pcm16Bytes] raw PCM16 audio; [sampleRate] the capture rate.
/// Outputs: an 8-value feature vector.
List<double> extractClassifierFeatures(Uint8List pcm16Bytes, {int sampleRate = micSampleRate}) {
  final profile = computeSpectralProfile(pcm16Bytes, sampleRate: sampleRate);
  final amplitude = computeAmplitude(pcm16Bytes);
  final zeroCrossingRate = computeZeroCrossingRate(pcm16Bytes);
  return [...profile, amplitude, zeroCrossingRate];
}
