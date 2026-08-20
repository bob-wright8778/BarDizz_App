import 'dart:typed_data';

/// Wraps mono PCM16 audio in a canonical RIFF/WAVE header -- the inverse of
/// [readWav] (wav_reader.dart) for the single-channel 16-bit case this app
/// only ever produces.
///
/// Inputs: [pcm16MonoBytes] raw little-endian PCM16 mono audio bytes;
/// [sampleRate] the capture sample rate.
/// Outputs: a complete WAV file's bytes (44-byte header + the PCM data).
Uint8List writeWav(Uint8List pcm16MonoBytes, {required int sampleRate}) {
  const channels = 1;
  const bitsPerSample = 16;
  final dataSize = pcm16MonoBytes.length;
  final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
  final blockAlign = channels * bitsPerSample ~/ 8;

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
  header.setUint16(34, bitsPerSample, Endian.little);
  setTag(36, 'data');
  header.setUint32(40, dataSize, Endian.little);

  final bytes = Uint8List(44 + dataSize);
  bytes.setRange(0, 44, header.buffer.asUint8List());
  bytes.setRange(44, 44 + dataSize, pcm16MonoBytes);
  return bytes;
}
