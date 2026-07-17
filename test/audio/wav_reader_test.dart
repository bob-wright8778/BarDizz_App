import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/wav_reader.dart';

Uint8List _buildWav({
  required int sampleRate,
  required int channels,
  required List<int> interleavedSamples,
}) {
  final dataBytes = ByteData(interleavedSamples.length * 2);
  for (var i = 0; i < interleavedSamples.length; i++) {
    dataBytes.setInt16(i * 2, interleavedSamples[i], Endian.little);
  }
  final dataSize = dataBytes.lengthInBytes;
  final byteRate = sampleRate * channels * 2;
  final blockAlign = channels * 2;

  final header = ByteData(44);
  void setTag(int offset, String tag) {
    for (var i = 0; i < 4; i++) {
      header.setUint8(offset + i, tag.codeUnitAt(i));
    }
  }

  setTag(0, 'RIFF');
  header.setUint32(4, 36 + dataSize, Endian.little);
  setTag(8, 'WAVE');
  setTag(12, 'fmt ');
  header.setUint32(16, 16, Endian.little);
  header.setUint16(20, 1, Endian.little); // PCM format tag
  header.setUint16(22, channels, Endian.little);
  header.setUint32(24, sampleRate, Endian.little);
  header.setUint32(28, byteRate, Endian.little);
  header.setUint16(32, blockAlign, Endian.little);
  header.setUint16(34, 16, Endian.little); // bits per sample
  setTag(36, 'data');
  header.setUint32(40, dataSize, Endian.little);

  final bytes = Uint8List(44 + dataSize);
  bytes.setRange(0, 44, header.buffer.asUint8List());
  bytes.setRange(44, 44 + dataSize, dataBytes.buffer.asUint8List());
  return bytes;
}

void main() {
  group('readWav', () {
    test('parses a mono PCM16 WAV file', () {
      final bytes = _buildWav(
        sampleRate: 16000,
        channels: 1,
        interleavedSamples: [100, -200, 300],
      );
      final wav = readWav(bytes);

      expect(wav.sampleRate, 16000);
      final samples = ByteData.sublistView(wav.pcm16Mono);
      expect(samples.getInt16(0, Endian.little), 100);
      expect(samples.getInt16(2, Endian.little), -200);
      expect(samples.getInt16(4, Endian.little), 300);
    });

    test('downmixes a stereo PCM16 WAV file by averaging channels', () {
      final bytes = _buildWav(
        sampleRate: 44100,
        channels: 2,
        interleavedSamples: [100, 300], // one frame: left=100, right=300
      );
      final wav = readWav(bytes);

      expect(wav.sampleRate, 44100);
      expect(wav.pcm16Mono.length, 2);
      final samples = ByteData.sublistView(wav.pcm16Mono);
      expect(samples.getInt16(0, Endian.little), 200);
    });

    test('throws FormatException for non-WAV data', () {
      expect(() => readWav(Uint8List.fromList([1, 2, 3, 4])), throwsFormatException);
    });

    test('throws FormatException for an unsupported bit depth', () {
      final bytes = _buildWav(sampleRate: 16000, channels: 1, interleavedSamples: [100]);
      ByteData.sublistView(bytes).setUint16(34, 8, Endian.little);

      expect(() => readWav(bytes), throwsFormatException);
    });

    test('throws FormatException for an unsupported channel count', () {
      final bytes = _buildWav(
        sampleRate: 16000,
        channels: 6,
        interleavedSamples: List.filled(6, 100),
      );

      expect(() => readWav(bytes), throwsFormatException);
    });
  });
}
