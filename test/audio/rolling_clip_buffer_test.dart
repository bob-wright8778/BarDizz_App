import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/rolling_clip_buffer.dart';

/// A one-sample-per-byte-pair PCM16 chunk with values 0, 1, 2, ... so a
/// slice's exact sample identities (not just its length) are checkable.
Uint8List _countingChunk(int startValue, int sampleCount) {
  final bytes = ByteData(sampleCount * 2);
  for (var i = 0; i < sampleCount; i++) {
    bytes.setInt16(i * 2, startValue + i, Endian.little);
  }
  return bytes.buffer.asUint8List();
}

List<int> _samplesOf(Uint8List pcm16Bytes) {
  final data = ByteData.sublistView(pcm16Bytes);
  return [for (var i = 0; i < pcm16Bytes.length; i += 2) data.getInt16(i, Endian.little)];
}

void main() {
  group('RollingClipBuffer', () {
    test('slices preRoll samples before and postRoll samples after a tap', () {
      final buffer = RollingClipBuffer(
        sampleRate: 10,
        preRoll: const Duration(milliseconds: 500), // 5 samples
        postRoll: const Duration(milliseconds: 300), // 3 samples
      );

      buffer.append(_countingChunk(0, 5)); // samples 0-4
      final tap = buffer.markTap(); // tap right after sample 4 arrived
      buffer.append(_countingChunk(5, 3)); // samples 5-7 (post-roll arrives)

      expect(buffer.isReady(tap), isTrue);
      expect(_samplesOf(buffer.sliceClip(tap)), [0, 1, 2, 3, 4, 5, 6, 7]);
    });

    test('is not ready until enough post-roll audio has arrived', () {
      final buffer = RollingClipBuffer(
        sampleRate: 10,
        preRoll: const Duration(milliseconds: 200),
        postRoll: const Duration(milliseconds: 300), // 3 samples
      );

      buffer.append(_countingChunk(0, 5));
      final tap = buffer.markTap();
      buffer.append(_countingChunk(5, 2)); // only 2 of 3 post-roll samples

      expect(buffer.isReady(tap), isFalse);

      buffer.append(_countingChunk(7, 1)); // the 3rd post-roll sample arrives
      expect(buffer.isReady(tap), isTrue);
    });

    test('a forced slice before post-roll fully arrives returns a shorter clip', () {
      final buffer = RollingClipBuffer(
        sampleRate: 10,
        preRoll: const Duration(milliseconds: 200), // 2 samples
        postRoll: const Duration(milliseconds: 500), // 5 samples
      );

      buffer.append(_countingChunk(0, 5)); // samples 0-4
      final tap = buffer.markTap(); // after sample 4
      buffer.append(_countingChunk(5, 1)); // only sample 5 arrives before Stop

      expect(buffer.isReady(tap), isFalse);
      // Forced (Stop-flush): whatever arrived so far, not an error.
      expect(_samplesOf(buffer.sliceClip(tap)), [3, 4, 5]);
    });

    test('a clip requested for a tap older than the retention window is truncated at the front',
        () {
      final buffer = RollingClipBuffer(
        sampleRate: 10,
        preRoll: const Duration(milliseconds: 500), // 5 samples
        postRoll: const Duration(milliseconds: 200), // 2 samples
      );

      buffer.append(_countingChunk(0, 5));
      final tap = buffer.markTap(); // wants samples [-5, 0) pre-roll, none exist yet
      buffer.append(_countingChunk(5, 2));

      expect(_samplesOf(buffer.sliceClip(tap)), [0, 1, 2, 3, 4, 5, 6]);
    });

    test('retains only preRoll+postRoll worth of history, evicting older audio', () {
      final buffer = RollingClipBuffer(
        sampleRate: 10,
        preRoll: const Duration(milliseconds: 200), // 2 samples
        postRoll: const Duration(milliseconds: 200), // 2 samples
      );

      buffer.append(_countingChunk(0, 10)); // samples 0-9, way more than retained
      final tap = buffer.markTap(); // right after sample 9
      buffer.append(_countingChunk(10, 2)); // samples 10-11 (post-roll)

      // Only the last 2 pre-roll samples (8, 9) should have survived eviction.
      expect(_samplesOf(buffer.sliceClip(tap)), [8, 9, 10, 11]);
    });
  });
}
