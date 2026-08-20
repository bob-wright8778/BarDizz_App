import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/wav_reader.dart';
import 'package:hockey_shot_tracker/audio/wav_writer.dart';

Uint8List _pcm16Of(List<int> samples) {
  final bytes = ByteData(samples.length * 2);
  for (var i = 0; i < samples.length; i++) {
    bytes.setInt16(i * 2, samples[i], Endian.little);
  }
  return bytes.buffer.asUint8List();
}

void main() {
  group('writeWav', () {
    test('round-trips through readWav with identical sample rate and PCM', () {
      final pcm = _pcm16Of([100, -200, 300, 0, 32767, -32768]);

      final wavBytes = writeWav(pcm, sampleRate: 16000);
      final decoded = readWav(wavBytes);

      expect(decoded.sampleRate, 16000);
      expect(decoded.pcm16Mono, pcm);
    });

    test('round-trips an empty clip', () {
      final wavBytes = writeWav(Uint8List(0), sampleRate: 16000);
      final decoded = readWav(wavBytes);

      expect(decoded.sampleRate, 16000);
      expect(decoded.pcm16Mono, isEmpty);
    });

    test('writes a valid RIFF/WAVE header', () {
      final wavBytes = writeWav(_pcm16Of([1, 2, 3]), sampleRate: 16000);

      expect(String.fromCharCodes(wavBytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wavBytes.sublist(8, 12)), 'WAVE');
    });
  });
}
