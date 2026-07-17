import 'dart:typed_data';

import 'shot_detector.dart';
import 'wav_reader.dart';

/// Number of shot detections a [ShotDetector] fires while consuming an
/// entire clip's audio, streamed in fixed-size chunks the same way live
/// capture delivers them — used to score recorded test clips for the
/// hit-rate/false-positive-rate accuracy check.
///
/// Inputs: [wav] decoded clip audio; [config] detector tuning ([config]'s
/// `sampleRate` should match `wav.sampleRate`); [chunkSampleCount] samples
/// per simulated stream chunk.
/// Outputs: total number of shots the detector counted in this clip.
int countDetections(
  WavAudio wav, {
  ShotDetectorConfig config = const ShotDetectorConfig(),
  int chunkSampleCount = 320,
}) {
  var clock = DateTime(2026);
  final detector = ShotDetector(config: config, now: () => clock);

  final bytesPerChunk = chunkSampleCount * 2;
  final chunkDuration = Duration(
    microseconds: (chunkSampleCount * 1000000 / config.sampleRate).round(),
  );

  var detections = 0;
  for (var offset = 0; offset < wav.pcm16Mono.length; offset += bytesPerChunk) {
    final end = (offset + bytesPerChunk < wav.pcm16Mono.length)
        ? offset + bytesPerChunk
        : wav.pcm16Mono.length;
    final chunk = Uint8List.sublistView(wav.pcm16Mono, offset, end);
    if (detector.detect(chunk)) detections++;
    clock = clock.add(chunkDuration);
  }
  return detections;
}
