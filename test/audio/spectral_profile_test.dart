import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/spectral_profile.dart';

Uint8List _pureTone(double freq, {int sampleRate = 16000, int sampleCount = 320}) {
  final bytes = ByteData(sampleCount * 2);
  for (var i = 0; i < sampleCount; i++) {
    final value = math.sin(2 * math.pi * freq * i / sampleRate);
    bytes.setInt16(i * 2, (value * 32767).round(), Endian.little);
  }
  return bytes.buffer.asUint8List();
}

void main() {
  group('computeSpectralProfile', () {
    test('empty buffer returns an all-zero profile', () {
      final profile = computeSpectralProfile(Uint8List(0));
      expect(profile, everyElement(0.0));
      expect(profile.length, spectralBandCenters.length);
    });

    test('silence returns an all-zero profile', () {
      final profile = computeSpectralProfile(Uint8List(640));
      expect(profile, everyElement(0.0));
    });

    test('a pure tone at a band center puts most energy in that band', () {
      const bandIndex = 2; // 2000Hz
      final profile = computeSpectralProfile(_pureTone(spectralBandCenters[bandIndex]));

      expect(profile[bandIndex], greaterThan(0.8));
      final othersSum =
          profile.fold<double>(0.0, (sum, v) => sum + v) - profile[bandIndex];
      expect(othersSum, lessThan(0.2));
    });

    test('profile values always sum to ~1.0 for non-silent input', () {
      final profile = computeSpectralProfile(_pureTone(1000));
      final sum = profile.fold<double>(0.0, (s, v) => s + v);
      expect(sum, closeTo(1.0, 0.001));
    });
  });

  group('defaultShotSpectralProfile', () {
    test('matches the values derived from real shot recordings on 2026-07-17', () {
      // Locks in tool/derive_profile.dart's output against silent drift --
      // see spectral_profile.dart's doc comment for the derivation method.
      expect(
        defaultShotSpectralProfile,
        [0.5121, 0.3161, 0.0727, 0.0588, 0.0183, 0.0220],
      );
    });

    test('is low-frequency-dominant, matching real shots through this mic pipeline', () {
      final lowBandEnergy = defaultShotSpectralProfile[0] + defaultShotSpectralProfile[1];
      final highBandEnergy = defaultShotSpectralProfile
          .sublist(2)
          .fold<double>(0.0, (sum, v) => sum + v);
      expect(lowBandEnergy, greaterThan(highBandEnergy));
    });
  });

  group('cosineSimilarity', () {
    test('identical vectors have similarity 1.0', () {
      expect(cosineSimilarity([0.2, 0.3, 0.5], [0.2, 0.3, 0.5]), closeTo(1.0, 0.0001));
    });

    test('orthogonal vectors have similarity 0.0', () {
      expect(cosineSimilarity([1.0, 0.0], [0.0, 1.0]), closeTo(0.0, 0.0001));
    });

    test('a zero vector has similarity 0.0 rather than dividing by zero', () {
      expect(cosineSimilarity([0.0, 0.0], [1.0, 1.0]), 0.0);
    });
  });
}
