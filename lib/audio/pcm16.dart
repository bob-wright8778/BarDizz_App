import 'dart:typed_data';

/// Decodes raw little-endian PCM16 bytes into signed sample values.
///
/// Inputs: [pcm16Bytes] raw PCM16 audio bytes (a trailing odd byte is dropped).
/// Outputs: one signed 16-bit sample per two input bytes, in order.
List<int> decodePcm16(Uint8List pcm16Bytes) {
  final sampleCount = pcm16Bytes.length ~/ 2;
  if (sampleCount == 0) return const [];

  final byteData = ByteData.sublistView(pcm16Bytes, 0, sampleCount * 2);
  return List<int>.generate(sampleCount, (i) => byteData.getInt16(i * 2, Endian.little));
}
