import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/clip_evaluator.dart';
import 'package:hockey_shot_tracker/audio/shot_detector.dart';
import 'package:hockey_shot_tracker/audio/spectral_profile.dart';
import 'package:hockey_shot_tracker/audio/wav_reader.dart';

Uint8List _sineChunk(
  List<MapEntry<double, double>> componentsFreqAmp, {
  int sampleRate = 16000,
  int sampleCount = 320,
}) {
  final bytes = ByteData(sampleCount * 2);
  for (var i = 0; i < sampleCount; i++) {
    var value = 0.0;
    for (final component in componentsFreqAmp) {
      value += component.value * math.sin(2 * math.pi * component.key * i / sampleRate);
    }
    final clamped = value.clamp(-1.0, 1.0);
    bytes.setInt16(i * 2, (clamped * 32767).round(), Endian.little);
  }
  return bytes.buffer.asUint8List();
}

Uint8List _shotLikeChunk({int sampleRate = 16000}) {
  final components = [
    for (var i = 0; i < spectralBandCenters.length; i++)
      MapEntry(spectralBandCenters[i], math.sqrt(defaultShotSpectralProfile[i])),
  ];
  return _sineChunk(components, sampleRate: sampleRate);
}

Uint8List _silenceChunk({int sampleCount = 320}) => Uint8List(sampleCount * 2);

Uint8List _concat(List<Uint8List> chunks) {
  final total = chunks.fold<int>(0, (sum, c) => sum + c.length);
  final out = Uint8List(total);
  var offset = 0;
  for (final chunk in chunks) {
    out.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }
  return out;
}

void main() {
  group('countDetections', () {
    test('counts one detection for a clip with a single shot surrounded by silence', () {
      final clip = WavAudio(
        sampleRate: 16000,
        pcm16Mono: _concat([_silenceChunk(), _shotLikeChunk(), _silenceChunk(), _silenceChunk()]),
      );

      expect(countDetections(clip), 1);
    });

    test('a silent clip has zero detections', () {
      final clip = WavAudio(sampleRate: 16000, pcm16Mono: _silenceChunk(sampleCount: 1280));
      expect(countDetections(clip), 0);
    });

    test('two shots far enough apart to clear the refractory window both count', () {
      final gap = List.generate(20, (_) => _silenceChunk()); // 20 * 20ms = 400ms
      final clip = WavAudio(
        sampleRate: 16000,
        pcm16Mono: _concat([_shotLikeChunk(), ...gap, _shotLikeChunk()]),
      );

      expect(countDetections(clip), 2);
    });

    test('honors a non-default sample rate passed via config', () {
      const sampleRate = 32000;
      final clip = WavAudio(
        sampleRate: sampleRate,
        pcm16Mono: _concat([_silenceChunk(), _shotLikeChunk(sampleRate: sampleRate)]),
      );

      final detections = countDetections(
        clip,
        config: const ShotDetectorConfig(sampleRate: sampleRate),
      );
      expect(detections, 1);
    });
  });
}
