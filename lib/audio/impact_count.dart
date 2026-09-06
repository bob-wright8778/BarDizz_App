import 'dart:math' as math;

import 'amplitude.dart';
import 'audio_constants.dart';

/// Tunables for [countImpacts]. Defaults reflect stick/puck acoustics at
/// 16kHz: a 10ms envelope frame resolves impacts ~50ms apart, and only
/// impacts within 12dB (x0.25) of the window's loudest frame are counted so
/// a shot's decaying tail and soft net rattle never register as extra hits.
class ImpactCountConfig {
  const ImpactCountConfig({
    this.frameDuration = const Duration(milliseconds: 10),
    this.relativeFloor = 0.25,
    this.releaseRatio = 0.5,
    this.minGap = const Duration(milliseconds: 50),
    this.absoluteFloor = 0.02,
  });

  final Duration frameDuration;

  /// An impact counts only if its frame RMS is at least this fraction of the
  /// window's peak frame RMS.
  final double relativeFloor;

  /// After an impact, the envelope must fall below `floor * releaseRatio`
  /// before another impact can be counted (hysteresis).
  final double releaseRatio;

  /// Minimum spacing between counted impacts.
  final Duration minGap;

  /// Frames quieter than this RMS (0.0-1.0) never count, whatever the peak.
  final double absoluteFloor;
}

/// Counts distinct impacts in one window from its short-frame RMS envelope.
/// A single shot yields 1 (or 2 if the puck strikes something loud inside
/// the window); stick handling yields one per tap.
///
/// Inputs: [samples] signed 16-bit PCM samples; [sampleRate] capture rate;
/// [config] envelope tunables.
/// Outputs: the number of impacts, 0 for silence.
int countImpacts(
  List<int> samples, {
  int sampleRate = micSampleRate,
  ImpactCountConfig config = const ImpactCountConfig(),
}) {
  final envelope = frameRmsEnvelope(samples, sampleRate: sampleRate, frameDuration: config.frameDuration);
  if (envelope.isEmpty) return 0;

  final peak = envelope.reduce(math.max);
  final floor = math.max(config.absoluteFloor, peak * config.relativeFloor);
  if (peak < config.absoluteFloor) return 0;

  final minGapFrames = math.max(1, (config.minGap.inMicroseconds / config.frameDuration.inMicroseconds).round());
  var count = 0;
  var armed = true;
  var lastImpactFrame = -minGapFrames;
  for (var i = 0; i < envelope.length; i++) {
    final level = envelope[i];
    if (armed) {
      if (level < floor) continue;
      armed = false;
      if (i - lastImpactFrame >= minGapFrames) {
        count++;
        lastImpactFrame = i;
      }
    } else if (level < floor * config.releaseRatio) {
      armed = true;
    }
  }
  return count;
}

/// Splits [samples] into consecutive [frameDuration] frames and returns each
/// frame's normalized RMS (0.0-1.0). A trailing partial frame is dropped.
///
/// Inputs: [samples] signed 16-bit PCM samples; [sampleRate] capture rate.
/// Outputs: one RMS value per full frame.
List<double> frameRmsEnvelope(
  List<int> samples, {
  int sampleRate = micSampleRate,
  Duration frameDuration = const Duration(milliseconds: 10),
}) {
  final frameLength = (sampleRate * frameDuration.inMicroseconds / Duration.microsecondsPerSecond).round();
  if (frameLength <= 0 || samples.length < frameLength) return const [];

  final frameCount = samples.length ~/ frameLength;
  return List<double>.generate(
    frameCount,
    (f) => computeAmplitudeFromSamples(samples.sublist(f * frameLength, (f + 1) * frameLength)),
  );
}
