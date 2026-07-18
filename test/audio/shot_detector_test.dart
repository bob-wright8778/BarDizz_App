import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/amplitude.dart';
import 'package:hockey_shot_tracker/audio/shot_detector.dart';
import 'package:hockey_shot_tracker/audio/spectral_profile.dart';

import 'synthetic_audio.dart';

Uint8List _shotLikeChunk() => chunkMatching(defaultShotSpectralProfile);

Uint8List _quietTone() => sineWave([const MapEntry(150.0, 0.02)]);

// A pure tone at the highest analyzed band, the opposite end of the
// spectrum from [defaultShotSpectralProfile]'s low-frequency-dominant real
// shape (derived from real recordings -- see spectral_profile.dart) -- a
// low-frequency tone would leak into the same low bands the profile now
// emphasizes and no longer represent a mismatched shape.
Uint8List _loudWrongShapeChunk() => sineWave([const MapEntry(6000.0, 0.9)]);

Uint8List _silence() => silentChunk();

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

    test('a loud chunk with the wrong spectral shape (high-frequency whine) does not count', () {
      final detector = ShotDetector();
      expect(detector.detect(_loudWrongShapeChunk()), isFalse);
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

    test('detectFromFeatures matches detect given the same chunk\'s precomputed features', () {
      final detector = ShotDetector();
      final chunk = _shotLikeChunk();
      final amplitude = computeAmplitude(chunk);
      final profile = computeSpectralProfile(chunk);
      expect(detector.detectFromFeatures(amplitude, profile), isTrue);
    });
  });
}
