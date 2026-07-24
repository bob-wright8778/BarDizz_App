import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/pcm16.dart';
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

    test('delegates to computeSpectralProfileFromSamples on the decoded samples', () {
      final bytes = _pureTone(1000);
      final samples = decodePcm16(bytes);
      expect(computeSpectralProfile(bytes), computeSpectralProfileFromSamples(samples));
    });
  });

  group('computeSpectralProfileFromSamples', () {
    test('empty list returns an all-zero profile', () {
      final profile = computeSpectralProfileFromSamples(const []);
      expect(profile, everyElement(0.0));
    });

    test('a pure tone at a band center puts most energy in that band', () {
      const bandIndex = 2; // 2000Hz
      final profile = computeSpectralProfileFromSamples(
        decodePcm16(_pureTone(spectralBandCenters[bandIndex])),
      );

      expect(profile[bandIndex], greaterThan(0.8));
    });
  });
}
