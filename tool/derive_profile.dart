// ignore_for_file: avoid_print
// One-off derivation of a new default shot spectral profile from a directory
// of real shot clips: finds each clip's peak-amplitude chunk, computes its
// spectral profile, and averages across clips (same math as
// deriveReferenceProfile). Prints the result as a Dart list literal.
//
// Usage: dart run tool/derive_profile.dart <shots-dir>
import 'dart:io';

import 'package:hockey_shot_tracker/audio/calibration_profile.dart';
import 'package:hockey_shot_tracker/audio/spectral_profile.dart';
import 'package:hockey_shot_tracker/audio/wav_chunker.dart';
import 'package:hockey_shot_tracker/audio/wav_reader.dart';

import 'cli_helpers.dart';

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/derive_profile.dart <shots-dir>');
    exitCode = 64;
    return;
  }

  final dir = requireDirectory(args[0]);
  if (dir == null) return;

  final peakProfiles = <List<double>>[];

  for (final file in listWavFiles(dir)) {
    final wav = readWav(file.readAsBytesSync());
    final chunks = chunkWav(wav);
    final peakIdx = peakChunkIndex(chunks);
    if (peakIdx == -1) {
      stderr.writeln('Skipping empty clip: ${file.path}');
      continue;
    }

    final profile = computeSpectralProfile(chunks[peakIdx], sampleRate: wav.sampleRate);
    peakProfiles.add(profile);
    print('${file.path}: profile=$profile');
  }

  if (peakProfiles.isEmpty) {
    stderr.writeln('No usable clips found in ${dir.path}.');
    exitCode = 1;
    return;
  }

  final avg = deriveReferenceProfile(peakProfiles);
  print('');
  print('Averaged profile (${peakProfiles.length} clips):');
  print(avg.map((v) => v.toStringAsFixed(4)).toList());
}
