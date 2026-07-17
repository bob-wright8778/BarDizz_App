import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/shot_detector.dart';
import 'package:hockey_shot_tracker/audio/spectral_profile.dart';

Uint8List _sineWave(
  List<MapEntry<double, double>> componentsFreqAmp, {
  int sampleRate = 16000,
  int sampleCount = 320,
}) {
  final bytes = ByteData(sampleCount * 2);
  for (var i = 0; i < sampleCount; i++) {
    var value = 0.0;
    for (final component in componentsFreqAmp) {
      value += component.value * math.sin(2 * math.pi * component.key * i / sampleRate);
    }
    final clamped = value.clamp(-1.0, 1.0);
    bytes.setInt16(i * 2, (clamped * 32767).round(), Endian.little);
  }
  return bytes.buffer.asUint8List();
}

/// A synthetic "shot" chunk shaped to match [defaultShotSpectralProfile]:
/// one tone per band, amplitude proportional to that band's target energy.
Uint8List _shotLikeChunk() {
  final components = [
    for (var i = 0; i < spectralBandCenters.length; i++)
      MapEntry(spectralBandCenters[i], math.sqrt(defaultShotSpectralProfile[i])),
  ];
  return _sineWave(components);
}

Uint8List _quietTone() => _sineWave([const MapEntry(150.0, 0.02)]);

Uint8List _loudLowThud() => _sineWave([const MapEntry(150.0, 0.9)]);

Uint8List _silence() => Uint8List(640);

void main() {
  group('ShotDetector', () {
    test('a loud chunk matching the reference spectral shape counts as a shot', () {
      final detector = ShotDetector();
      expect(detector.detect(_shotLikeChunk()), isTrue);
    });

    test('silence never counts as a shot', () {
      final detector = ShotDetector();
      expect(detector.detect(_silence()), isFalse);
    });

    test('a quiet chunk below the amplitude threshold does not count, even if shaped right', () {
      final detector = ShotDetector();
      expect(detector.detect(_quietTone()), isFalse);
    });

    test('a loud chunk with the wrong spectral shape (low-frequency thud) does not count', () {
      final detector = ShotDetector();
      expect(detector.detect(_loudLowThud()), isFalse);
    });

    test('refractory window blocks a second match immediately after the first', () {
      var now = DateTime(2026);
      final detector = ShotDetector(now: () => now);

      expect(detector.detect(_shotLikeChunk()), isTrue);
      now = now.add(const Duration(milliseconds: 50));
      expect(
        detector.detect(_shotLikeChunk()),
        isFalse,
        reason: 'echo/reverb within the refractory window should not double-count',
      );
    });

    test('a match after the refractory window elapses counts again', () {
      var now = DateTime(2026);
      final detector = ShotDetector(now: () => now);

      expect(detector.detect(_shotLikeChunk()), isTrue);
      now = now.add(const Duration(milliseconds: 300));
      expect(detector.detect(_shotLikeChunk()), isTrue);
    });
  });
}
