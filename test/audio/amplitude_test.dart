import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/amplitude.dart';

Uint8List pcm16Of(List<int> samples) {
  final bytes = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    bytes.setInt16(i * 2, samples[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
}

void main() {
  group('computeAmplitude', () {
    test('empty buffer returns 0.0', () {
      expect(computeAmplitude(Uint8List(0)), 0.0);
    });

    test('silence (all-zero samples) returns 0.0', () {
      expect(computeAmplitude(pcm16Of([0, 0, 0, 0])), 0.0);
    });

    test('full-scale samples return ~1.0', () {
      final amplitude = computeAmplitude(pcm16Of([32767, -32768, 32767, -32768]));
      expect(amplitude, closeTo(1.0, 0.001));
    });

    test('half-scale constant samples return ~0.5', () {
      final amplitude = computeAmplitude(pcm16Of([16384, 16384, 16384]));
      expect(amplitude, closeTo(0.5, 0.001));
    });

    test('result is always clamped within 0.0-1.0', () {
      final amplitude = computeAmplitude(pcm16Of([32767, -32768]));
      expect(amplitude, inInclusiveRange(0.0, 1.0));
    });

    test('trailing odd byte is ignored rather than throwing', () {
      final evenBytes = pcm16Of([100, 200]);
      final withTrailingByte = Uint8List(evenBytes.length + 1)
        ..setRange(0, evenBytes.length, evenBytes);
      expect(
        () => computeAmplitude(withTrailingByte),
        returnsNormally,
      );
    });

    test('delegates to computeAmplitudeFromSamples on the decoded samples', () {
      final samples = [32767, -32768, 16384, 0];
      expect(computeAmplitude(pcm16Of(samples)), computeAmplitudeFromSamples(samples));
    });
  });

  group('computeAmplitudeFromSamples', () {
    test('empty list returns 0.0', () {
      expect(computeAmplitudeFromSamples(const []), 0.0);
    });

    test('all-zero samples return 0.0', () {
      expect(computeAmplitudeFromSamples(const [0, 0, 0, 0]), 0.0);
    });

    test('full-scale samples return ~1.0', () {
      final amplitude = computeAmplitudeFromSamples(const [32767, -32768, 32767, -32768]);
      expect(amplitude, closeTo(1.0, 0.001));
    });
  });
}
