// ignore_for_file: avoid_print
// Accuracy validation for ticket 02 (detection engine): runs a recorded set
// of real stick-puck impact clips, plus common false-positive clips, through
// ShotDetector and reports hit rate / false-positive rate.
//
// Usage:
//   dart run tool/evaluate_detector.dart <shots-dir> <false-positives-dir>
//
// Each directory should contain 16-bit PCM WAV clips (mono or stereo, any
// sample rate) — one clip per sound. "Shots" clips should each contain
// exactly one stick-puck impact; "false positive" clips should contain none.
import 'dart:io';

import 'package:hockey_shot_tracker/audio/clip_evaluator.dart';
import 'package:hockey_shot_tracker/audio/shot_detector.dart';
import 'package:hockey_shot_tracker/audio/wav_reader.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln(
      'Usage: dart run tool/evaluate_detector.dart <shots-dir> <false-positives-dir>',
    );
    exitCode = 64;
    return;
  }

  final shotsResult = _evaluateDirectory(Directory(args[0]));
  final falsePositiveResult = _evaluateDirectory(Directory(args[1]));

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

List<_ClipResult> _evaluateDirectory(Directory dir) {
  if (!dir.existsSync()) {
    stderr.writeln('Directory not found: ${dir.path}');
    exitCode = 1;
    return [];
  }

  final results = <_ClipResult>[];
  final files = dir.listSync()
    ..sort((a, b) => a.path.compareTo(b.path));
  for (final entity in files) {
    if (entity is! File || !entity.path.toLowerCase().endsWith('.wav')) continue;
    final wav = readWav(entity.readAsBytesSync());
    final config = ShotDetectorConfig(sampleRate: wav.sampleRate);
    results.add(_ClipResult(entity.path, countDetections(wav, config: config)));
  }
  return results;
}
