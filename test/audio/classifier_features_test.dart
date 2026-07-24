import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/amplitude.dart';
import 'package:hockey_shot_tracker/audio/classifier_features.dart';
import 'package:hockey_shot_tracker/audio/pcm16.dart';
import 'package:hockey_shot_tracker/audio/spectral_profile.dart';

Uint8List _pcm16(List<int> samples) {
  final bytes = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    bytes.setInt16(i * 2, samples[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
}

void main() {
  group('computeZeroCrossingRate', () {
    test('empty buffer is 0.0', () {
      expect(computeZeroCrossingRate(Uint8List(0)), 0.0);
    });

    test('single sample is 0.0', () {
      expect(computeZeroCrossingRate(_pcm16([100])), 0.0);
    });

    test('constant sign has no crossings', () {
      expect(computeZeroCrossingRate(_pcm16([100, 200, 300, 50])), 0.0);
    });

    test('fully alternating sign crosses every adjacent pair', () {
      final rate = computeZeroCrossingRate(_pcm16([100, -100, 100, -100, 100]));
      expect(rate, closeTo(1.0, 0.0001));
    });

    test('one crossing in four samples', () {
      // pairs: 100->200 (no), 200->-50 (yes), -50->-10 (no) => 1 of 3
      final rate = computeZeroCrossingRate(_pcm16([100, 200, -50, -10]));
      expect(rate, closeTo(1 / 3, 0.0001));
    });

    test('zero is treated as non-negative', () {
      // 100->0 (no crossing), 0->-5 (crossing) => 1 of 2
      final rate = computeZeroCrossingRate(_pcm16([100, 0, -5]));
      expect(rate, closeTo(0.5, 0.0001));
    });

    test('delegates to computeZeroCrossingRateFromSamples on the decoded samples', () {
      final samples = [100, -100, 100, -100, 100];
      expect(computeZeroCrossingRate(_pcm16(samples)), computeZeroCrossingRateFromSamples(samples));
    });
  });

  group('computeZeroCrossingRateFromSamples', () {
    test('empty list is 0.0', () {
      expect(computeZeroCrossingRateFromSamples(const []), 0.0);
    });

    test('single sample is 0.0', () {
      expect(computeZeroCrossingRateFromSamples(const [100]), 0.0);
    });

    test('fully alternating sign crosses every adjacent pair', () {
      final rate = computeZeroCrossingRateFromSamples(const [100, -100, 100, -100, 100]);
      expect(rate, closeTo(1.0, 0.0001));
    });
  });

  group('extractClassifierFeatures', () {
    test('returns 8 values in classifierFeatureNames order', () {
      final features = extractClassifierFeatures(_pcm16(List.filled(400, 1000)));
      expect(features.length, 8);
      expect(classifierFeatureNames.length, 8);
    });

    test('empty clip is all zeros', () {
      final features = extractClassifierFeatures(Uint8List(0));
      expect(features, everyElement(0.0));
    });

    test('matches the underlying spectral/amplitude/zcr functions directly', () {
      final pcm16Bytes = _pcm16(List.generate(400, (i) => (i.isEven ? 3000 : -2500)));
      final features = extractClassifierFeatures(pcm16Bytes);

      final expectedProfile = computeSpectralProfile(pcm16Bytes);
      final expectedAmplitude = computeAmplitude(pcm16Bytes);
      final expectedZcr = computeZeroCrossingRate(pcm16Bytes);

      expect(features.sublist(0, 6), expectedProfile);
      expect(features[6], expectedAmplitude);
      expect(features[7], expectedZcr);
    });

    test('matches the *FromSamples functions computed off one shared decode', () {
      final pcm16Bytes = _pcm16(List.generate(400, (i) => (i.isEven ? 3000 : -2500)));
      final features = extractClassifierFeatures(pcm16Bytes);

      final samples = decodePcm16(pcm16Bytes);
      final expectedProfile = computeSpectralProfileFromSamples(samples);
      final expectedAmplitude = computeAmplitudeFromSamples(samples);
      final expectedZcr = computeZeroCrossingRateFromSamples(samples);

      expect(features.sublist(0, 6), expectedProfile);
      expect(features[6], expectedAmplitude);
      expect(features[7], expectedZcr);
    });
  });
}
