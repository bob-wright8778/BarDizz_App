// ignore_for_file: avoid_print
// Ticket 02 (on-device ML classifier task) spot-check: for each WAV file
// path given, prints its Dart-computed classifier feature vector and
// classifySound() prediction -- for manually diffing against
// tool/ml_investigation/train_dart_classifier.py's Python-side
// extract_dart_features()/model.predict() on the same file, confirming the
// Dart port produces the same feature values and predictions as the Python
// training-side code (spec acceptance criteria). Full held-out-set replay
// validation is ticket 04's job; this is a small manual cross-check tool.
//
// Usage:
//   dart run tool/spot_check_classifier.dart <clip.wav> [<clip.wav> ...]
import 'dart:io';

import 'package:hockey_shot_tracker/audio/classifier_features.dart';
import 'package:hockey_shot_tracker/audio/sound_classifier.dart';
import 'package:hockey_shot_tracker/audio/wav_reader.dart';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln('Usage: dart run tool/spot_check_classifier.dart <clip.wav> [<clip.wav> ...]');
    exitCode = 64;
    return;
  }

  for (final path in args) {
    final file = File(path);
    if (!file.existsSync()) {
      stderr.writeln('File not found: $path');
      exitCode = 1;
      continue;
    }

    final wav = readWav(file.readAsBytesSync());
    final features = extractClassifierFeatures(wav.pcm16Mono, sampleRate: wav.sampleRate);
    final predicted = classifySound(features);

    print(path);
    for (var i = 0; i < classifierFeatureNames.length; i++) {
      print('  ${classifierFeatureNames[i]}: ${features[i]}');
    }
    print('  predicted: $predicted');
  }
}
