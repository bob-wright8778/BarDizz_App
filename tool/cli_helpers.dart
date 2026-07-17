// Shared CLI helpers for the tuning tools (evaluate_detector.dart,
// analyze_clips.dart, derive_profile.dart): directory validation and WAV
// file listing.
import 'dart:io';

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
