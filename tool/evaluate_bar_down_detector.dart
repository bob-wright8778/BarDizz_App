// ignore_for_file: avoid_print
// Accuracy validation for ticket 03 (bar-hit vs. shot discrimination): runs a
// recorded set of real bar-hit clips, plus regular shot clips, through
// BarDownDetector's bar-hit stage only and reports hit rate / false-positive
// rate -- mirrors tool/evaluate_detector.dart's ShotDetector pattern.
//
// Usage:
//   dart run tool/evaluate_bar_down_detector.dart <bar-hits-dir> <shots-dir> [barHitAmplitudeThreshold] [barHitSpectralMatchThreshold]
//
// Each directory should contain 16-bit PCM WAV clips (mono or stereo, any
// sample rate). "Bar-hits" clips should each contain a real crossbar impact
// (the bar-hit stage should match); "shots" clips contain regular
// stick-puck impacts with no crossbar hit (the bar-hit stage should NOT
// match -- a match means the confirm window would spuriously open). The two
// optional trailing args override BarDownDetectorConfig's bar-hit defaults,
// for sweeping threshold combinations during tuning without editing the
// config.
import 'package:hockey_shot_tracker/audio/bar_down_clip_evaluator.dart';
import 'package:hockey_shot_tracker/audio/bar_down_detector.dart';
import 'package:hockey_shot_tracker/audio/spectral_profile.dart';
import 'package:hockey_shot_tracker/audio/wav_reader.dart';

import 'cli_helpers.dart';

void main(List<String> args) {
  const usage =
      'Usage: dart run tool/evaluate_bar_down_detector.dart <bar-hits-dir> <shots-dir> '
      '[barHitAmplitudeThreshold] [barHitSpectralMatchThreshold]';
  final overrides = parseThresholdArgs(args, usage);
  if (overrides == null) return;
  final (amplitudeThreshold, spectralMatchThreshold) = overrides;

  const defaults = BarDownDetectorConfig(ewwReferenceProfile: defaultBarHitSpectralProfile);
  BarDownDetectorConfig buildConfig(WavAudio wav) => BarDownDetectorConfig(
    ewwReferenceProfile: defaultBarHitSpectralProfile,
    barHitAmplitudeThreshold: amplitudeThreshold ?? defaults.barHitAmplitudeThreshold,
    barHitSpectralMatchThreshold: spectralMatchThreshold ?? defaults.barHitSpectralMatchThreshold,
    sampleRate: wav.sampleRate,
  );
  int countMatches(WavAudio wav, BarDownDetectorConfig config) => countBarHitMatches(wav, config: config);

  final barHitResult = evaluateDirectory(args[0], buildConfig, countMatches);
  final shotsResult = evaluateDirectory(args[1], buildConfig, countMatches);

  printClipResults('Bar-hits', args[0], barHitResult, hitWord: 'HIT ', missWord: 'MISS', rateLabel: 'Hit rate');
  print('');
  printClipResults(
    'Shots',
    args[1],
    shotsResult,
    hitWord: 'FALSE POSITIVE',
    missWord: 'clean',
    rateLabel: 'False-positive rate',
  );
}
