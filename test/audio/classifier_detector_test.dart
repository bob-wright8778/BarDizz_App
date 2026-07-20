import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/classifier_detector.dart';
import 'package:hockey_shot_tracker/audio/classifier_features.dart';

import 'synthetic_audio.dart';

/// Deterministic stand-in for the real 200-tree classifier: returns
/// [labels] in call order (repeating the last one past the end), recording
/// every feature vector it was called with, so windowing/refractory/confirm-
/// window mechanics can be tested without depending on real audio shaping a
/// specific real-model prediction.
class _FakeClassifier {
  _FakeClassifier(this.labels);

  final List<String> labels;
  final List<List<double>> callFeatures = [];
  int _index = 0;

  String call(List<double> features) {
    callFeatures.add(features);
    final label = labels[_index < labels.length ? _index : labels.length - 1];
    _index++;
    return label;
  }
}

Uint8List _loudChunk({int sampleCount = 320}) => sineWave([const MapEntry(1000.0, 0.9)], sampleCount: sampleCount);

Uint8List _quietChunk({int sampleCount = 320}) => sineWave([const MapEntry(1000.0, 0.02)], sampleCount: sampleCount);

void main() {
  group('ClassifierDetector windowing', () {
    test('a quiet chunk below the amplitude threshold never opens a window', () {
      final fake = _FakeClassifier(['shot']);
      final detector = ClassifierDetector(classify: fake.call);

      expect(detector.detect(_quietChunk()), isNull);
      expect(fake.callFeatures, isEmpty);
    });

    test('a loud chunk opens a window that is not classified until it reaches the configured length', () {
      final fake = _FakeClassifier(['shot']);
      final detector = ClassifierDetector(
        config: const ClassifierDetectorConfig(windowDuration: Duration(milliseconds: 40)), // 2 chunks @16kHz/320
        classify: fake.call,
      );

      expect(detector.detect(_loudChunk()), isNull, reason: 'only 1 of 2 chunks collected so far');
      expect(fake.callFeatures, isEmpty);
    });

    test('a window is classified exactly once it reaches the configured length', () {
      final fake = _FakeClassifier(['shot']);
      final detector = ClassifierDetector(
        config: const ClassifierDetectorConfig(windowDuration: Duration(milliseconds: 40)),
        classify: fake.call,
      );

      expect(detector.detect(_loudChunk()), isNull);
      expect(detector.detect(_quietChunk()), ClassifiedEvent.shot);
      expect(fake.callFeatures, hasLength(1));
      expect(detector.lastLabel, 'shot');
    });

    test('the classified window is exactly the concatenation of every chunk since the trigger', () {
      final fake = _FakeClassifier(['shot']);
      final detector = ClassifierDetector(
        config: const ClassifierDetectorConfig(windowDuration: Duration(milliseconds: 40)),
        classify: fake.call,
      );
      final chunk1 = _loudChunk();
      final chunk2 = _quietChunk();

      detector.detect(chunk1);
      detector.detect(chunk2);

      final combined = concatChunks([chunk1, chunk2]);
      final expectedFeatures = _referenceFeatures(combined);
      expect(fake.callFeatures.single, expectedFeatures);
    });

    test('a trigger-worthy chunk arriving mid-window does not restart the window', () {
      // windowDuration = 3 chunks. If a loud 2nd chunk restarted the window
      // (judgment call: it should not), a 3rd chunk would still leave the
      // (restarted) window short by one chunk, and classify would not yet
      // have been called.
      final fake = _FakeClassifier(['shot']);
      final detector = ClassifierDetector(
        config: const ClassifierDetectorConfig(windowDuration: Duration(milliseconds: 60)),
        classify: fake.call,
      );
      final chunk1 = _loudChunk();
      final chunk2 = _loudChunk(); // also loud -- must not reopen the window
      final chunk3 = _quietChunk();

      expect(detector.detect(chunk1), isNull);
      expect(detector.detect(chunk2), isNull);
      expect(detector.detect(chunk3), ClassifiedEvent.shot, reason: 'the window completed on the 3rd chunk, not a 4th');
      expect(fake.callFeatures, hasLength(1));
      expect(fake.callFeatures.single, _referenceFeatures(concatChunks([chunk1, chunk2, chunk3])));
    });
  });

  group('ClassifierDetector refractory', () {
    test('refractory blocks the next trigger immediately after a classification, whatever the label', () {
      var now = DateTime(2026);
      final fake = _FakeClassifier(['background-quiet', 'shot']);
      final detector = ClassifierDetector(
        config: const ClassifierDetectorConfig(windowDuration: Duration(milliseconds: 20), refractoryWindow: Duration(milliseconds: 250)),
        now: () => now,
        classify: fake.call,
      );

      expect(detector.detect(_loudChunk()), isNull, reason: 'background-quiet resolves to no event');
      expect(fake.callFeatures, hasLength(1));

      now = now.add(const Duration(milliseconds: 50));
      expect(detector.detect(_loudChunk()), isNull, reason: 'still inside the 250ms refractory window');
      expect(fake.callFeatures, hasLength(1), reason: 'refractory blocks a new window from even opening');
    });

    test('a trigger after the refractory window elapses opens a new window', () {
      var now = DateTime(2026);
      final fake = _FakeClassifier(['background-quiet', 'shot']);
      final detector = ClassifierDetector(
        config: const ClassifierDetectorConfig(windowDuration: Duration(milliseconds: 20), refractoryWindow: Duration(milliseconds: 250)),
        now: () => now,
        classify: fake.call,
      );

      detector.detect(_loudChunk());
      now = now.add(const Duration(milliseconds: 300));
      expect(detector.detect(_loudChunk()), ClassifiedEvent.shot);
      expect(fake.callFeatures, hasLength(2));
    });
  });

  group('ClassifierDetector event resolution', () {
    test('background-quiet and stick-handling classifications report no event', () {
      final fake = _FakeClassifier(['background-quiet', 'stick-handling']);
      var now = DateTime(2026);
      final detector = ClassifierDetector(
        config: const ClassifierDetectorConfig(windowDuration: Duration(milliseconds: 20)),
        now: () => now,
        classify: fake.call,
      );

      expect(detector.detect(_loudChunk()), isNull);
      now = now.add(const Duration(milliseconds: 300));
      expect(detector.detect(_loudChunk()), isNull);
    });

    test('shot reports ClassifiedEvent.shot immediately, no confirm window needed', () {
      final fake = _FakeClassifier(['shot']);
      final detector = ClassifierDetector(
        config: const ClassifierDetectorConfig(windowDuration: Duration(milliseconds: 20)),
        classify: fake.call,
      );

      expect(detector.detect(_loudChunk()), ClassifiedEvent.shot);
    });

    test('a standalone eww with no pending bar-hit reports no event', () {
      final fake = _FakeClassifier(['eww']);
      final detector = ClassifierDetector(
        config: const ClassifierDetectorConfig(windowDuration: Duration(milliseconds: 20)),
        classify: fake.call,
      );

      expect(detector.detect(_loudChunk()), isNull);
    });

    test('a bar-hit followed by a confirming eww within the confirm window reports a bar-down', () {
      var now = DateTime(2026);
      final fake = _FakeClassifier(['bar-hit', 'eww']);
      final detector = ClassifierDetector(
        config: const ClassifierDetectorConfig(
          windowDuration: Duration(milliseconds: 20),
          refractoryWindow: Duration(milliseconds: 250),
          barDownConfirmWindow: Duration(seconds: 2),
        ),
        now: () => now,
        classify: fake.call,
      );

      expect(detector.detect(_loudChunk()), isNull, reason: 'the bar-hit itself is not a bar down');
      now = now.add(const Duration(milliseconds: 500));
      expect(detector.detect(_loudChunk()), ClassifiedEvent.barDown);
    });

    test('a bar-hit with no confirming eww before the confirm window expires is silently dropped', () {
      var now = DateTime(2026);
      final fake = _FakeClassifier(['bar-hit', 'eww']);
      final detector = ClassifierDetector(
        config: const ClassifierDetectorConfig(
          windowDuration: Duration(milliseconds: 20),
          refractoryWindow: Duration(milliseconds: 50),
          barDownConfirmWindow: Duration(milliseconds: 300),
        ),
        now: () => now,
        classify: fake.call,
      );

      expect(detector.detect(_loudChunk()), isNull);
      now = now.add(const Duration(milliseconds: 400)); // past the 300ms confirm window
      expect(
        detector.detect(_loudChunk()),
        isNull,
        reason: 'the confirm window already expired, so this eww is a standalone one',
      );
    });

    test('a second bar-hit while a confirm window is open does not reopen or extend it', () {
      var now = DateTime(2026);
      final fake = _FakeClassifier(['bar-hit', 'bar-hit', 'eww']);
      final detector = ClassifierDetector(
        config: const ClassifierDetectorConfig(
          windowDuration: Duration(milliseconds: 20),
          refractoryWindow: Duration(milliseconds: 50),
          barDownConfirmWindow: Duration(milliseconds: 300),
        ),
        now: () => now,
        classify: fake.call,
      );

      expect(detector.detect(_loudChunk()), isNull, reason: 'the first bar-hit opens the confirm window at t=0');
      now = now.add(const Duration(milliseconds: 100));
      expect(
        detector.detect(_loudChunk()),
        isNull,
        reason: 'a 2nd bar-hit inside the window is tested only as a possible eww, and rejected',
      );
      now = now.add(const Duration(milliseconds: 250)); // t=350ms: past the original 300ms deadline
      expect(
        detector.detect(_loudChunk()),
        isNull,
        reason: 'the confirm window was never extended by the 2nd bar-hit, so it has already expired',
      );
    });

    test('a shot while a bar-hit confirm window is open is still reported immediately', () {
      var now = DateTime(2026);
      final fake = _FakeClassifier(['bar-hit', 'shot', 'eww']);
      final detector = ClassifierDetector(
        config: const ClassifierDetectorConfig(
          windowDuration: Duration(milliseconds: 20),
          refractoryWindow: Duration(milliseconds: 50),
          barDownConfirmWindow: Duration(milliseconds: 300),
        ),
        now: () => now,
        classify: fake.call,
      );

      expect(detector.detect(_loudChunk()), isNull, reason: 'the bar-hit opens the confirm window at t=0');
      now = now.add(const Duration(milliseconds: 100));
      expect(
        detector.detect(_loudChunk()),
        ClassifiedEvent.shot,
        reason: 'a real shot inside an open confirm window must still be reported immediately',
      );
      now = now.add(const Duration(milliseconds: 100)); // t=200ms: still inside the 300ms deadline
      expect(
        detector.detect(_loudChunk()),
        ClassifiedEvent.barDown,
        reason: 'the shot did not disturb the pending confirm window -- the later eww still confirms it',
      );
    });
  });

  group('ClassifierDetector real-model wiring smoke test', () {
    test('a real triggered window is classified via the real extractClassifierFeatures/classifySound path', () {
      // No fake classifier here -- exercises the actual default wiring
      // (ClassifierDetector()'s default `classify: classifySound`). A pure
      // synthetic sine burst is not representative training audio, so the
      // resulting label isn't meaningful as an accuracy check (ticket 2's
      // spot-check already covers that against real clips) -- this only
      // proves the plumbing (real feature extraction + real 200-tree
      // ensemble) runs end to end without throwing, and is deterministic.
      final detector = ClassifierDetector();
      final burst = sineWave([const MapEntry(2000.0, 0.9)], sampleCount: 320); // 640 bytes, well above the gate
      final rest = silentChunk(sampleCount: 12800 - 320); // completes the default 800ms/12800-sample window

      expect(detector.detect(burst), isNull, reason: 'window not yet full');
      final event = detector.detect(rest);

      expect(detector.lastLabel, 'eww', reason: 'deterministic real-model output for this exact synthetic fixture');
      expect(event, isNull, reason: 'a standalone eww with no pending bar-hit reports no event');
    });
  });
}

/// Recomputes the feature vector a real window's bytes would produce, for
/// asserting [_FakeClassifier] was called with exactly the accumulated
/// window (not a partial or shifted one).
List<double> _referenceFeatures(Uint8List windowBytes) => extractClassifierFeatures(windowBytes);
