import 'bar_down_detector.dart';
import 'wav_chunker.dart';
import 'wav_reader.dart';

/// Placeholder Eww profile for isolated bar-hit-stage evaluation --
/// [BarDownDetectorConfig.ewwReferenceProfile] has no default (it's always
/// per-user calibrated in production, see that field's doc comment), but
/// [countBarHitMatches] only inspects the bar-hit stage, so any profile
/// works here. Picked to be spectrally distinct from a bar-hit shape so it
/// can't accidentally match a bar-hit-shaped chunk while a window is open.
const _placeholderEwwProfile = [0.02, 0.03, 0.05, 0.10, 0.30, 0.50];

/// Number of times a [BarDownDetector]'s bar-hit stage matches (opens a
/// confirm window) while consuming an entire clip's audio, streamed in
/// fixed-size chunks the same way live capture delivers them -- mirrors
/// [countDetections]'s role for `ShotDetector`, but scores only the bar-hit
/// stage, not a full confirmed bar down (these test clips contain no real
/// "Eww", so completion isn't what's being evaluated).
///
/// Inputs: [wav] decoded clip audio; [config] bar-hit tuning to test
/// ([config]'s `sampleRate` should match `wav.sampleRate`; `ewwReferenceProfile`
/// is irrelevant here, see [_placeholderEwwProfile]); [chunkSampleCount]
/// samples per simulated stream chunk.
/// Outputs: total number of times the bar-hit stage matched in this clip.
int countBarHitMatches(
  WavAudio wav, {
  BarDownDetectorConfig config = const BarDownDetectorConfig(ewwReferenceProfile: _placeholderEwwProfile),
  int chunkSampleCount = defaultChunkSampleCount,
}) {
  var clock = DateTime(2026);
  final detector = BarDownDetector(config: config, now: () => clock);
  final chunkDuration = Duration(
    microseconds: (chunkSampleCount * 1000000 / config.sampleRate).round(),
  );

  for (final chunk in chunkWav(wav, chunkSampleCount: chunkSampleCount)) {
    detector.detect(chunk);
    clock = clock.add(chunkDuration);
  }
  return detector.barHitMatches;
}
