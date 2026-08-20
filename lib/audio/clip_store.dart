import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'collection_label.dart';

/// Persists/deletes labeled data-collection clips. Abstracted from
/// [LiveDataCollectionController] (data_collection_controller.dart) so tests
/// never touch the real filesystem.
abstract class ClipStore {
  /// Saves [wavBytes] under this store's data-collection root, returning the
  /// path it was saved to (later passed back to [deleteClip] for undo).
  Future<String> writeClip({
    required CollectionLabel label,
    required Uint8List wavBytes,
    required DateTime timestamp,
  });

  Future<void> deleteClip(String path);
}

/// Writes clips under `<external files dir>/data_collection/<label>/`,
/// retrievable later via `adb pull` or a file manager -- this app has no
/// backend for raw audio (offline-first design, matching the rest of the
/// app). Falls back to the app documents directory where external storage
/// isn't available (iOS has no external storage concept).
class FileClipStore implements ClipStore {
  const FileClipStore();

  @override
  Future<String> writeClip({
    required CollectionLabel label,
    required Uint8List wavBytes,
    required DateTime timestamp,
  }) async {
    final dir = await _labelDir(label);
    await dir.create(recursive: true);
    final file = File('${dir.path}/${label.folderName}_${_formatTimestamp(timestamp)}.wav');
    await file.writeAsBytes(wavBytes, flush: true);
    return file.path;
  }

  @override
  Future<void> deleteClip(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  Future<Directory> _labelDir(CollectionLabel label) async {
    final base = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    return Directory('${base.path}/data_collection/${label.folderName}');
  }
}

String _formatTimestamp(DateTime t) {
  String pad(int n, [int width = 2]) => n.toString().padLeft(width, '0');
  return '${t.year}${pad(t.month)}${pad(t.day)}_'
      '${pad(t.hour)}${pad(t.minute)}${pad(t.second)}_${pad(t.millisecond, 3)}';
}
