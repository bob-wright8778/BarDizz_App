import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/pcm16.dart';

Uint8List _pcm16(List<int> samples) {
  final bytes = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    bytes.setInt16(i * 2, samples[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
}

void main() {
  group('decodePcm16', () {
    test('empty buffer decodes to an empty list', () {
      expect(decodePcm16(Uint8List(0)), isEmpty);
    });

    test('decodes little-endian signed 16-bit samples in order', () {
      expect(decodePcm16(_pcm16([0, 100, -100, 32767, -32768])), [0, 100, -100, 32767, -32768]);
    });

    test('trailing odd byte is dropped rather than throwing', () {
      final evenBytes = _pcm16([100, 200]);
      final withTrailingByte = Uint8List(evenBytes.length + 1)
        ..setRange(0, evenBytes.length, evenBytes);
      expect(decodePcm16(withTrailingByte), [100, 200]);
    });
  });
}
