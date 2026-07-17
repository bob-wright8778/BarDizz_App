import 'dart:typed_data';

import 'amplitude.dart';
import 'wav_reader.dart';

const defaultChunkSampleCount = 320;

/// Splits [wav] into fixed-size PCM16 chunks (the last chunk may be shorter)
/// — the same fixed-size streaming chunks live capture feeds the detector.
List<Uint8List> chunkWav(WavAudio wav, {int chunkSampleCount = defaultChunkSampleCount}) {
  final bytesPerChunk = chunkSampleCount * 2;
  final chunks = <Uint8List>[];
  for (var offset = 0; offset < wav.pcm16Mono.length; offset += bytesPerChunk) {
    final end = (offset + bytesPerChunk < wav.pcm16Mono.length)
        ? offset + bytesPerChunk
        : wav.pcm16Mono.length;
    chunks.add(Uint8List.sublistView(wav.pcm16Mono, offset, end));
  }
  return chunks;
}

/// Index of the loudest chunk in [chunks], or -1 if [chunks] is empty.
int peakChunkIndex(List<Uint8List> chunks) {
  if (chunks.isEmpty) return -1;
  var peakIdx = 0;
  var peakAmp = computeAmplitude(chunks[0]);
  for (var i = 1; i < chunks.length; i++) {
    final amp = computeAmplitude(chunks[i]);
    if (amp > peakAmp) {
      peakAmp = amp;
      peakIdx = i;
    }
  }
  return peakIdx;
}
