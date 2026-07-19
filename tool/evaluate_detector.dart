// ignore_for_file: avoid_print
// Accuracy validation for ticket 02 (detection engine): runs a recorded set
// of real stick-puck impact clips, plus common false-positive clips, through
// ShotDetector and reports hit rate / false-positive rate.
//
// Usage:
//   dart run tool/evaluate_detector.dart <shots-dir> <false-positives-dir> [amplitudeThreshold] [spectralMatchThreshold]
//
// Each directory should contain 16-bit PCM WAV clips (mono or stereo, any
// sample rate) — one clip per sound. "Shots" clips should each contain
// exactly one stick-puck impact; "false positive" clips should contain none.
// The two optional trailing args override ShotDetectorConfig's defaults, for
// sweeping threshold combinations during tuning without editing the config.
import 'package:hockey_shot_tracker/audio/clip_evaluator.dart';
import 'package:hockey_shot_tracker/audio/shot_detector.dart';
import 'package:hockey_shot_tracker/audio/wav_reader.dart';

import 'cli_helpers.dart';

void main(List<String> args) {
  const usage =
      'Usage: dart run tool/evaluate_detector.dart <shots-dir> <false-positives-dir> '
      '[amplitudeThreshold] [spectralMatchThreshold]';
  final overrides = parseThresholdArgs(args, usage);
  if (overrides == null) return;
  final (amplitudeThreshold, spectralMatchThreshold) = overrides;

  const defaults = ShotDetectorConfig();
  ShotDetectorConfig buildConfig(WavAudio wav) => ShotDetectorConfig(
    amplitudeThreshold: amplitudeThreshold ?? defaults.amplitudeThreshold,
    spectralMatchThreshold: spectralMatchThreshold ?? defaults.spectralMatchThreshold,
    sampleRate: wav.sampleRate,
  );
  int countMatches(WavAudio wav, ShotDetectorConfig config) => countDetections(wav, config: config);

  final shotsResult = evaluateDirectory(args[0], buildConfig, countMatches);
  final falsePositiveResult = evaluateDirectory(args[1], buildConfig, countMatches);

  printClipResults('Shots', args[0], shotsResult, hitWord: 'HIT ', missWord: 'MISS', rateLabel: 'Hit rate');
  print('');
  printClipResults(
    'False-positive',
    args[1],
    falsePositiveResult,
    hitWord: 'FALSE POSITIVE',
    missWord: 'clean',
    rateLabel: 'False-positive rate',
  );
}
