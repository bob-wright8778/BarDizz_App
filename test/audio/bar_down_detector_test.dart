import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/amplitude.dart';
import 'package:hockey_shot_tracker/audio/bar_down_detector.dart';
import 'package:hockey_shot_tracker/audio/spectral_profile.dart';

import 'synthetic_audio.dart';

// High-frequency-weighted, the opposite end of the spectrum from
// [defaultBarHitSpectralProfile]'s low-frequency-dominant impact shape --
// stands in for a per-user calibrated "Eww" profile without depending on the
// calibration flow (that's a separate ticket).
const _testEwwProfile = [0.02, 0.03, 0.05, 0.10, 0.30, 0.50];

Uint8List _barHitChunk() => chunkMatching(defaultBarHitSpectralProfile);

Uint8List _ewwChunk() => chunkMatching(_testEwwProfile);

Uint8List _quietTone() => sineWave([const MapEntry(150.0, 0.02)]);

Uint8List _silence() => silentChunk();

BarDownDetectorConfig _config({Duration confirmWindow = const Duration(seconds: 2)}) =>
    BarDownDetectorConfig(ewwReferenceProfile: _testEwwProfile, confirmWindow: confirmWindow);

void main() {
  group('BarDownDetectorConfig', () {
    test('barHitSpectralMatchThreshold defaults to 0.99', () {
      // Locks in the ticket-03 retune against silent drift -- see this
      // field's doc comment (bar_down_detector.dart) and
      // dev/contexts/hockey-shot-tracker.md in AI_Workspace for the
      // threshold-sweep evidence behind this value.
      const config = BarDownDetectorConfig(ewwReferenceProfile: _testEwwProfile);
      expect(config.barHitSpectralMatchThreshold, 0.99);
    });
  });

  group('BarDownDetector', () {
    test('a bar-hit followed by a confirming Eww within the window reports a bar down', () {
      var now = DateTime(2026);
      final detector = BarDownDetector(config: _config(), now: () => now);

      expect(detector.detect(_barHitChunk()), isFalse, reason: 'the bar-hit itself is not a bar down');
      now = now.add(const Duration(milliseconds: 500));
      expect(detector.detect(_ewwChunk()), isTrue);
    });

    test('Eww detected an instant before the window closes still counts', () {
      var now = DateTime(2026);
      final detector = BarDownDetector(config: _config(), now: () => now);

      expect(detector.detect(_barHitChunk()), isFalse);
      now = now.add(const Duration(milliseconds: 1999));
      expect(detector.detect(_ewwChunk()), isTrue);
    });

    test('a bar-hit with no Eww before the window closes reports nothing', () {
      var now = DateTime(2026);
      final detector = BarDownDetector(config: _config(), now: () => now);

      expect(detector.detect(_barHitChunk()), isFalse);
      now = now.add(const Duration(seconds: 3));
      expect(detector.detect(_silence()), isFalse);
    });

    test('Eww heard after the window has already closed does not count', () {
      var now = DateTime(2026);
      final detector = BarDownDetector(config: _config(), now: () => now);

      expect(detector.detect(_barHitChunk()), isFalse);
      now = now.add(const Duration(seconds: 3));
      expect(
        detector.detect(_ewwChunk()),
        isFalse,
        reason: 'a bar hit alone (no Eww inside the window) is silently dropped',
      );
    });

    test('a bar-hit alone, with no further input, never reports a bar down', () {
      final detector = BarDownDetector(config: _config());
      expect(detector.detect(_barHitChunk()), isFalse);
    });

    test('a quiet bar-hit-shaped chunk below the amplitude threshold does not start a window', () {
      var now = DateTime(2026);
      final detector = BarDownDetector(config: _config(), now: () => now);

      expect(detector.detect(_quietTone()), isFalse);
      now = now.add(const Duration(milliseconds: 500));
      expect(
        detector.detect(_ewwChunk()),
        isFalse,
        reason: 'no window was ever opened, so a later Eww should not count',
      );
    });

    test('silence never starts a window or reports a bar down', () {
      final detector = BarDownDetector(config: _config());
      expect(detector.detect(_silence()), isFalse);
    });

    test('bar-hit detection runs independently from the Eww window it opens', () {
      var now = DateTime(2026);
      final detector = BarDownDetector(config: _config(), now: () => now);

      // A second bar-hit while a window is already open is evaluated as a
      // potential Eww match (and correctly rejected), not as a new bar-hit.
      expect(detector.detect(_barHitChunk()), isFalse);
      now = now.add(const Duration(milliseconds: 200));
      expect(detector.detect(_barHitChunk()), isFalse);
      now = now.add(const Duration(milliseconds: 200));
      expect(detector.detect(_ewwChunk()), isTrue);
    });

    test('a confirmed bar down starts a refractory window that blocks an immediate repeat', () {
      var now = DateTime(2026);
      final detector = BarDownDetector(
        config: BarDownDetectorConfig(
          ewwReferenceProfile: _testEwwProfile,
          refractoryWindow: const Duration(milliseconds: 250),
        ),
        now: () => now,
      );

      expect(detector.detect(_barHitChunk()), isFalse);
      now = now.add(const Duration(milliseconds: 500));
      expect(detector.detect(_ewwChunk()), isTrue, reason: 'the first bar-hit+Eww counts');

      now = now.add(const Duration(milliseconds: 50));
      expect(
        detector.detect(_barHitChunk()),
        isFalse,
        reason: 'echo/reverb from the just-confirmed Eww should not open a new window',
      );
      now = now.add(const Duration(milliseconds: 500));
      expect(
        detector.detect(_ewwChunk()),
        isFalse,
        reason: 'no window is open, so a later Eww-shaped chunk alone should not count',
      );
    });

    test('a bar down after the refractory window elapses counts again', () {
      var now = DateTime(2026);
      final detector = BarDownDetector(
        config: BarDownDetectorConfig(
          ewwReferenceProfile: _testEwwProfile,
          refractoryWindow: const Duration(milliseconds: 250),
        ),
        now: () => now,
      );

      expect(detector.detect(_barHitChunk()), isFalse);
      now = now.add(const Duration(milliseconds: 500));
      expect(detector.detect(_ewwChunk()), isTrue);

      now = now.add(const Duration(milliseconds: 300));
      expect(detector.detect(_barHitChunk()), isFalse);
      now = now.add(const Duration(milliseconds: 500));
      expect(detector.detect(_ewwChunk()), isTrue, reason: 'a genuinely new bar down after refractory counts');
    });

    test('barHitMatches counts each independent bar-hit-stage match', () {
      var now = DateTime(2026);
      final detector = BarDownDetector(config: _config(), now: () => now);
      expect(detector.barHitMatches, 0);

      detector.detect(_barHitChunk());
      expect(detector.barHitMatches, 1, reason: 'the bar-hit stage matched and opened a window');

      now = now.add(const Duration(seconds: 3)); // let the window close unconfirmed
      detector.detect(_barHitChunk());
      expect(detector.barHitMatches, 2, reason: 'a second, independent bar-hit-stage match');
    });

    test('barHitMatches does not increment for a chunk evaluated as a possible Eww', () {
      var now = DateTime(2026);
      final detector = BarDownDetector(config: _config(), now: () => now);

      detector.detect(_barHitChunk());
      expect(detector.barHitMatches, 1);

      now = now.add(const Duration(milliseconds: 200));
      detector.detect(_barHitChunk()); // window is open; tested as an Eww candidate, not a bar-hit
      expect(
        detector.barHitMatches,
        1,
        reason: 'a chunk inside an open window is tested against the Eww profile, not the bar-hit stage',
      );
    });

    test('detectFromFeatures matches detect given the same chunk\'s precomputed features', () {
      var now = DateTime(2026);
      final detector = BarDownDetector(config: _config(), now: () => now);
      final barHitChunk = _barHitChunk();
      final ewwChunk = _ewwChunk();

      final barHitAmplitude = computeAmplitude(barHitChunk);
      final barHitProfile = computeSpectralProfile(barHitChunk);
      expect(detector.detectFromFeatures(barHitAmplitude, barHitProfile), isFalse);

      now = now.add(const Duration(milliseconds: 500));
      final ewwAmplitude = computeAmplitude(ewwChunk);
      final ewwProfile = computeSpectralProfile(ewwChunk);
      expect(detector.detectFromFeatures(ewwAmplitude, ewwProfile), isTrue);
    });
  });
}
