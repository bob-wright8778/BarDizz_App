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
import 'dart:io';

import 'package:hockey_shot_tracker/audio/clip_evaluator.dart';
import 'package:hockey_shot_tracker/audio/shot_detector.dart';
import 'package:hockey_shot_tracker/audio/wav_reader.dart';

import 'cli_helpers.dart';

void main(List<String> args) {
  if (args.length != 2 && args.length != 4) {
    stderr.writeln(
      'Usage: dart run tool/evaluate_detector.dart <shots-dir> <false-positives-dir> '
      '[amplitudeThreshold] [spectralMatchThreshold]',
    );
    exitCode = 64;
    return;
  }

  double? amplitudeThreshold;
  double? spectralMatchThreshold;
  if (args.length == 4) {
    amplitudeThreshold = double.tryParse(args[2]);
    spectralMatchThreshold = double.tryParse(args[3]);
    if (amplitudeThreshold == null || spectralMatchThreshold == null) {
      stderr.writeln('amplitudeThreshold and spectralMatchThreshold must be numbers.');
      exitCode = 64;
      return;
    }
  }

  final shotsResult = _evaluateDirectory(args[0], amplitudeThreshold, spectralMatchThreshold);
  final falsePositiveResult = _evaluateDirectory(args[1], amplitudeThreshold, spectralMatchThreshold);

  final hits = shotsResult.where((r) => r.detections >= 1).length;
  final falsePositives = falsePositiveResult.where((r) => r.detections >= 1).length;

  print('Shots directory: ${args[0]}');
  for (final r in shotsResult) {
    print('  ${r.detections >= 1 ? 'HIT ' : 'MISS'}  ${r.detections} detection(s)  ${r.path}');
  }
  print(
    'Hit rate: $hits/${shotsResult.length}'
    ' (${shotsResult.isEmpty ? 0 : (100 * hits / shotsResult.length).toStringAsFixed(1)}%)',
  );

  print('');
  print('False-positive directory: ${args[1]}');
  for (final r in falsePositiveResult) {
    print('  ${r.detections >= 1 ? 'FALSE POSITIVE' : 'clean'}  ${r.detections} detection(s)  ${r.path}');
  }
  print(
    'False-positive rate: $falsePositives/${falsePositiveResult.length}'
    ' (${falsePositiveResult.isEmpty ? 0 : (100 * falsePositives / falsePositiveResult.length).toStringAsFixed(1)}%)',
  );
}

class _ClipResult {
  _ClipResult(this.path, this.detections);
  final String path;
  final int detections;
}

List<_ClipResult> _evaluateDirectory(
  String path,
  double? amplitudeThreshold,
  double? spectralMatchThreshold,
) {
  final dir = requireDirectory(path);
  if (dir == null) return [];

  const defaults = ShotDetectorConfig();
  final results = <_ClipResult>[];
  for (final file in listWavFiles(dir)) {
    final wav = readWav(file.readAsBytesSync());
    final config = ShotDetectorConfig(
      amplitudeThreshold: amplitudeThreshold ?? defaults.amplitudeThreshold,
      spectralMatchThreshold: spectralMatchThreshold ?? defaults.spectralMatchThreshold,
      sampleRate: wav.sampleRate,
    );
    results.add(_ClipResult(file.path, countDetections(wav, config: config)));
  }
  return results;
}
