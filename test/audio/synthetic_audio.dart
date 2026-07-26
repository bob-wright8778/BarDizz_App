import 'dart:math' as math;
import 'dart:typed_data';

/// Synthesizes a PCM16 chunk from one or more sine components, for feeding
/// the detectors' amplitude-gate/classification logic in tests without real
/// audio.
///
/// Inputs: [componentsFreqAmp] (frequency Hz, amplitude) pairs to sum;
/// [sampleRate]/[sampleCount] the chunk's shape.
/// Outputs: a raw PCM16 buffer.
Uint8List sineWave(
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

/// A zeroed PCM16 buffer -- true digital silence.
Uint8List silentChunk({int sampleCount = 320}) => Uint8List(sampleCount * 2);

/// Joins PCM16 [chunks] end to end into one buffer, for building a synthetic
/// clip out of several chunks (e.g. silence -> a shaped chunk -> silence).
Uint8List concatChunks(List<Uint8List> chunks) {
  final total = chunks.fold<int>(0, (sum, c) => sum + c.length);
  final out = Uint8List(total);
  var offset = 0;
  for (final chunk in chunks) {
    out.setRange(offset, offset + chunk.length, chunk);
    offset += chunk.length;
  }
  return out;
}

/// The opening burst of a fixture that deterministically classifies as `eww` via the real 200-tree
/// model (not a fake classifier) -- shared by classifier_detector_test.dart's and
/// mic_level_controller_test.dart's real-model wiring tests. Pairs with [realEwwRestChunk]; 12800 = the
/// default 800ms window at the default 16kHz sample rate.
Uint8List realEwwBurstChunk() => sineWave([const MapEntry(2000.0, 0.9)], sampleCount: 320);

/// The trailing silence that completes [realEwwBurstChunk]'s default-length classification window.
Uint8List realEwwRestChunk() => silentChunk(sampleCount: 12800 - 320);
