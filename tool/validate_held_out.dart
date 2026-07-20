// ignore_for_file: avoid_print
// Ticket 04 (on-device ML classifier task): replays every held-out manifest
// clip through the full Dart pipeline (feature extraction + tree traversal)
// and confirms each prediction matches the retrained Python model's
// prediction exactly, per the ticket's offline-validation acceptance
// criterion. Reads the predictions dumped by
// tool/ml_investigation/validate_dart_predictions.py -- full-set counterpart
// to tool/spot_check_classifier.dart's manual 9-clip spot-check (ticket 02).
//
// Usage (after running the Python dump script):
//   dart run tool/validate_held_out.dart [<predictions.json>]
import 'dart:convert';
import 'dart:io';

import 'package:hockey_shot_tracker/audio/classifier_features.dart';
import 'package:hockey_shot_tracker/audio/sound_classifier.dart';
import 'package:hockey_shot_tracker/audio/wav_reader.dart';

void main(List<String> args) {
  final jsonPath =
      args.isNotEmpty ? args[0] : 'tool/ml_investigation/held_out_predictions.json';
  final file = File(jsonPath);
  if (!file.existsSync()) {
    stderr.writeln('Predictions file not found: $jsonPath');
    stderr.writeln('Run tool/ml_investigation/validate_dart_predictions.py first.');
    exitCode = 64;
    return;
  }

  final records = jsonDecode(file.readAsStringSync()) as List<dynamic>;
  var mismatches = 0;
  for (final record in records) {
    final map = record as Map<String, dynamic>;
    final path = map['path'] as String;
    final trueLabel = map['true_label'] as String;
    final pythonLabel = map['predicted_label'] as String;

    final wav = readWav(File(path).readAsBytesSync());
    final features = extractClassifierFeatures(wav.pcm16Mono, sampleRate: wav.sampleRate);
    final dartLabel = classifySound(features);

    if (dartLabel != pythonLabel) {
      mismatches++;
      print('MISMATCH $path (true=$trueLabel python=$pythonLabel dart=$dartLabel)');
    }
  }

  print('$mismatches mismatch(es) out of ${records.length} held-out clips.');
  if (mismatches > 0) exitCode = 1;
}
