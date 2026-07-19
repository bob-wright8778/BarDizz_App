// ignore_for_file: avoid_print
// Shared CLI helpers for the tuning tools (evaluate_detector.dart,
// evaluate_bar_down_detector.dart, analyze_clips.dart, derive_profile.dart):
// directory validation, WAV file listing, threshold-override arg parsing,
// and accuracy-evaluation reporting.
import 'dart:io';

import 'package:hockey_shot_tracker/audio/wav_reader.dart';

/// Returns [path] as a [Directory] if it exists, otherwise prints an error,
/// sets [exitCode], and returns null.
Directory? requireDirectory(String path) {
  final dir = Directory(path);
  if (!dir.existsSync()) {
    stderr.writeln('Directory not found: ${dir.path}');
    exitCode = 1;
    return null;
  }
  return dir;
}

/// Every `.wav` file directly in [dir], sorted by path.
List<File> listWavFiles(Directory dir) {
  final entries = dir.listSync()..sort((a, b) => a.path.compareTo(b.path));
  return entries.whereType<File>().where((f) => f.path.toLowerCase().endsWith('.wav')).toList();
}

/// Parses a tuning tool's two optional trailing threshold-override args.
/// Prints [usage] and sets [exitCode] on an invalid arg count or a
/// non-numeric override, in which case the caller should return immediately.
///
/// Inputs: [args] raw CLI arguments (expects exactly 2 or 4); [usage] the
/// usage line to print on error.
/// Outputs: `(amplitudeThreshold, spectralMatchThreshold)`, both null if no
/// overrides were given, or null (the whole tuple) if args were invalid.
(double?, double?)? parseThresholdArgs(List<String> args, String usage) {
  if (args.length != 2 && args.length != 4) {
    stderr.writeln(usage);
    exitCode = 64;
    return null;
  }
  if (args.length != 4) return (null, null);

  final amplitudeThreshold = double.tryParse(args[2]);
  final spectralMatchThreshold = double.tryParse(args[3]);
  if (amplitudeThreshold == null || spectralMatchThreshold == null) {
    stderr.writeln('Threshold overrides must be numbers.');
    exitCode = 64;
    return null;
  }
  return (amplitudeThreshold, spectralMatchThreshold);
}

/// One clip's evaluation result: its file path and how many times its
/// detector matched while consuming the clip.
class ClipResult {
  ClipResult(this.path, this.matchCount);
  final String path;
  final int matchCount;
}

/// Runs every WAV in [path] through [countMatches] with a per-file config
/// from [buildConfig] (so `sampleRate` can be set from each clip's own
/// header). Prints nothing; returns `[]` if [path] doesn't exist.
///
/// Inputs: [path] directory of WAV clips; [buildConfig] builds a config for
/// a decoded clip; [countMatches] scores a clip against a config.
/// Outputs: one [ClipResult] per WAV file found.
List<ClipResult> evaluateDirectory<TConfig>(
  String path,
  TConfig Function(WavAudio wav) buildConfig,
  int Function(WavAudio wav, TConfig config) countMatches,
) {
  final dir = requireDirectory(path);
  if (dir == null) return [];

  final results = <ClipResult>[];
  for (final file in listWavFiles(dir)) {
    final wav = readWav(file.readAsBytesSync());
    results.add(ClipResult(file.path, countMatches(wav, buildConfig(wav))));
  }
  return results;
}

/// Prints one directory's per-clip results plus its match-rate summary line.
///
/// Inputs: [label] directory kind (e.g. "Shots"); [path] the directory
/// passed on the CLI; [results] that directory's evaluated clips; [hitWord]/
/// [missWord] per-clip status labels for a match/no-match clip; [rateLabel]
/// the summary line's prefix (e.g. "Hit rate").
/// Outputs: none (writes to stdout).
void printClipResults(
  String label,
  String path,
  List<ClipResult> results, {
  required String hitWord,
  required String missWord,
  required String rateLabel,
}) {
  final matched = results.where((r) => r.matchCount >= 1).length;
  print('$label directory: $path');
  for (final r in results) {
    print('  ${r.matchCount >= 1 ? hitWord : missWord}  ${r.matchCount} match(es)  ${r.path}');
  }
  print(
    '$rateLabel: $matched/${results.length}'
    ' (${results.isEmpty ? 0 : (100 * matched / results.length).toStringAsFixed(1)}%)',
  );
}
