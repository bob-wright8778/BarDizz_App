import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/impact_count.dart';
import 'package:hockey_shot_tracker/audio/pcm16.dart';

import 'synthetic_audio.dart';

Uint8List _burst({double amplitude = 0.9, int sampleCount = 320}) =>
    sineWave([MapEntry(1000.0, amplitude)], sampleCount: sampleCount);

/// A burst that decays exponentially over [sampleCount] samples, like a
/// single impact ringing out.
Uint8List _decayingBurst({double amplitude = 0.9, int sampleCount = 3200}) {
  final raw = sineWave([MapEntry(1000.0, amplitude)], sampleCount: sampleCount);
  final samples = decodePcm16(raw);
  final out = ByteData(sampleCount * 2);
  for (var i = 0; i < sampleCount; i++) {
    final envelope = 1.0 - i / sampleCount;
    out.setInt16(i * 2, (samples[i] * envelope * envelope).round(), Endian.little);
  }
  return out.buffer.asUint8List();
}

int _count(List<Uint8List> chunks, {ImpactCountConfig config = const ImpactCountConfig()}) =>
    countImpacts(decodePcm16(concatChunks(chunks)), config: config);

void main() {
  group('frameRmsEnvelope', () {
    test('returns one RMS per full 10ms frame and drops a trailing partial frame', () {
      final env = frameRmsEnvelope(decodePcm16(_burst(sampleCount: 350)));
      expect(env, hasLength(2));
      expect(env[0], closeTo(0.636, 0.01));
    });

    test('is empty for input shorter than one frame', () {
      expect(frameRmsEnvelope(decodePcm16(_burst(sampleCount: 100))), isEmpty);
    });
  });

  group('countImpacts', () {
    test('silence has no impacts', () {
      expect(_count([silentChunk(sampleCount: 3200)]), 0);
    });

    test('one burst followed by silence is one impact', () {
      expect(_count([_burst(), silentChunk(sampleCount: 2880)]), 1);
    });

    test('a single decaying impact is one impact, not one per frame', () {
      expect(_count([_decayingBurst()]), 1);
    });

    test('a sustained tone with no release is one impact', () {
      expect(_count([_burst(sampleCount: 3200)]), 1);
    });

    test('three separated taps are three impacts', () {
      final gap = silentChunk(sampleCount: 960);
      expect(_count([_burst(), gap, _burst(), gap, _burst(), silentChunk(sampleCount: 320)]), 3);
    });

    test('a second impact far quieter than the peak is ignored', () {
      // 0.1 vs 0.9 peak: below the x0.25 relative floor.
      expect(_count([_burst(), silentChunk(sampleCount: 960), _burst(amplitude: 0.1), silentChunk(sampleCount: 1600)]), 1);
    });

    test('a second impact within 12dB of the peak counts', () {
      expect(_count([_burst(), silentChunk(sampleCount: 960), _burst(amplitude: 0.4), silentChunk(sampleCount: 1600)]), 2);
    });

    test('a dip that does not reach the release level does not re-arm', () {
      // Drops to 0.6x peak, above the 0.5 * 0.25 = 0.125x release point.
      expect(_count([_burst(), _burst(amplitude: 0.55, sampleCount: 960), _burst(), silentChunk(sampleCount: 1600)]), 1);
    });

    test('taps closer than minGap are merged', () {
      // 20ms burst, 20ms gap, 20ms burst: the second rises 40ms after the first.
      final config = const ImpactCountConfig(minGap: Duration(milliseconds: 50));
      expect(_count([_burst(), silentChunk(), _burst(), silentChunk(sampleCount: 2240)], config: config), 1);
    });

    test('everything below absoluteFloor is ignored', () {
      expect(_count([_burst(amplitude: 0.01), silentChunk(sampleCount: 2880)]), 0);
    });
  });
}
