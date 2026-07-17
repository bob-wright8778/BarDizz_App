import 'dart:typed_data';

/// Decoded WAV audio: PCM16 samples downmixed to a single channel.
class WavAudio {
  const WavAudio({required this.sampleRate, required this.pcm16Mono});

  final int sampleRate;
  final Uint8List pcm16Mono;
}

/// Parses a canonical PCM WAV file (RIFF/WAVE, 16-bit samples, mono or
/// stereo) for the shot-detector accuracy evaluation harness. Stereo input
/// is downmixed by averaging channels.
///
/// Inputs: [bytes] the full contents of a `.wav` file.
/// Outputs: the file's native sample rate plus little-endian PCM16 mono
/// bytes.
WavAudio readWav(Uint8List bytes) {
  if (bytes.length < 44 || _tag(bytes, 0) != 'RIFF' || _tag(bytes, 8) != 'WAVE') {
    throw const FormatException('Not a valid RIFF/WAVE file.');
  }

  int? sampleRate;
  int? channels;
  int? bitsPerSample;
  Uint8List? pcmData;

  final data = ByteData.sublistView(bytes);
  var offset = 12;
  while (offset + 8 <= bytes.length) {
    final chunkId = _tag(bytes, offset);
    final chunkSize = data.getUint32(offset + 4, Endian.little);
    final chunkStart = offset + 8;

    if (chunkId == 'fmt ') {
      final formatTag = data.getUint16(chunkStart, Endian.little);
      if (formatTag != 1) {
        throw FormatException(
          'Unsupported WAV format tag $formatTag (only uncompressed PCM is supported).',
        );
      }
      channels = data.getUint16(chunkStart + 2, Endian.little);
      sampleRate = data.getUint32(chunkStart + 4, Endian.little);
      bitsPerSample = data.getUint16(chunkStart + 14, Endian.little);
    } else if (chunkId == 'data') {
      pcmData = Uint8List.sublistView(bytes, chunkStart, chunkStart + chunkSize);
    }

    offset = chunkStart + chunkSize + (chunkSize.isOdd ? 1 : 0);
  }

  if (sampleRate == null || channels == null || bitsPerSample == null || pcmData == null) {
    throw const FormatException('WAV file is missing a fmt or data chunk.');
  }
  if (bitsPerSample != 16) {
    throw FormatException('Only 16-bit PCM WAV is supported (got $bitsPerSample-bit).');
  }
  if (channels != 1 && channels != 2) {
    throw FormatException('Only mono or stereo WAV is supported (got $channels channels).');
  }

  return WavAudio(
    sampleRate: sampleRate,
    pcm16Mono: channels == 1 ? pcmData : _downmixStereo(pcmData),
  );
}

String _tag(Uint8List bytes, int offset) =>
    String.fromCharCodes(bytes.sublist(offset, offset + 4));

Uint8List _downmixStereo(Uint8List stereoBytes) {
  final frameCount = stereoBytes.length ~/ 4;
  final stereoData = ByteData.sublistView(stereoBytes, 0, frameCount * 4);
  final monoBytes = ByteData(frameCount * 2);
  for (var i = 0; i < frameCount; i++) {
    final left = stereoData.getInt16(i * 4, Endian.little);
    final right = stereoData.getInt16(i * 4 + 2, Endian.little);
    monoBytes.setInt16(i * 2, (left + right) ~/ 2, Endian.little);
  }
  return monoBytes.buffer.asUint8List();
}
