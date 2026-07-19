import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/bar_down_clip_evaluator.dart';
import 'package:hockey_shot_tracker/audio/bar_down_detector.dart';
import 'package:hockey_shot_tracker/audio/spectral_profile.dart';
import 'package:hockey_shot_tracker/audio/wav_reader.dart';

import 'synthetic_audio.dart';

void main() {
  group('countBarHitMatches', () {
    test('counts one match for a clip with a single bar-hit-shaped chunk', () {
      final clip = WavAudio(
        sampleRate: 16000,
        pcm16Mono: concatChunks([silentChunk(), chunkMatching(defaultBarHitSpectralProfile), silentChunk()]),
      );
      expect(countBarHitMatches(clip), 1);
    });

    test('a silent clip has zero matches', () {
      final clip = WavAudio(sampleRate: 16000, pcm16Mono: silentChunk(sampleCount: 1280));
      expect(countBarHitMatches(clip), 0);
    });

    test('a centroid shot-shaped chunk still clears the real default bar-hit threshold', () {
      // defaultShotSpectralProfile and defaultBarHitSpectralProfile are
      // ~99.5% cosine-similar (see BarDownDetectorConfig's
      // barHitSpectralMatchThreshold doc comment) -- a chunk built from the
      // exact shot centroid clears the real 0.99 default. Individual real
      // shot clips vary around that centroid (measured 84.7% false-positive
      // rate, not 100%, see dev/contexts/hockey-shot-tracker.md in
      // AI_Workspace), but the centroid case itself does not discriminate.
      final clip = WavAudio(
        sampleRate: 16000,
        pcm16Mono: concatChunks([silentChunk(), chunkMatching(defaultShotSpectralProfile), silentChunk()]),
      );
      final matches = countBarHitMatches(
        clip,
        config: const BarDownDetectorConfig(ewwReferenceProfile: defaultBarHitSpectralProfile),
      );
      expect(matches, 1, reason: 'the real default does not reject a centroid shot chunk');
    });

    test('a stricter bar-hit spectral threshold override rejects a shot-shaped chunk', () {
      final clip = WavAudio(
        sampleRate: 16000,
        pcm16Mono: concatChunks([silentChunk(), chunkMatching(defaultShotSpectralProfile), silentChunk()]),
      );
      final matches = countBarHitMatches(
        clip,
        config: const BarDownDetectorConfig(
          ewwReferenceProfile: defaultBarHitSpectralProfile,
          barHitSpectralMatchThreshold: 0.999,
        ),
      );
      expect(matches, 0, reason: 'a shot-shaped chunk should not clear a near-1.0 bar-hit threshold');
    });

    test('honors a non-default sample rate passed via config', () {
      const sampleRate = 32000;
      final clip = WavAudio(
        sampleRate: sampleRate,
        pcm16Mono: concatChunks([
          silentChunk(),
          chunkMatching(defaultBarHitSpectralProfile, sampleRate: sampleRate),
        ]),
      );
      final matches = countBarHitMatches(
        clip,
        config: const BarDownDetectorConfig(
          ewwReferenceProfile: defaultBarHitSpectralProfile,
          sampleRate: sampleRate,
        ),
      );
      expect(matches, 1);
    });
  });
}
