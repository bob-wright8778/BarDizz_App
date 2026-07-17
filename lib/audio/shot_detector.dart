import 'dart:typed_data';

import 'amplitude.dart';
import 'audio_constants.dart';
import 'spectral_profile.dart';

/// Injectable clock, so the refractory window can be tested without real
/// wall-clock delays.
typedef Now = DateTime Function();

class ShotDetectorConfig {
  const ShotDetectorConfig({
    // Validated against 43 real shot / 2 false-positive recordings on
    // 2026-07-17 (tool/evaluate_detector.dart, tool/analyze_clips.dart):
    // 100% hit rate at this value with the real-data-derived
    // defaultShotSpectralProfile. A 20-combination sweep found no threshold
    // that also improves the false-positive rate without a much larger hit
    // to hit rate (see dev/contexts/hockey-shot-tracker.md in AI_Workspace)
    // -- kept unchanged rather than trading real misses for it.
    this.amplitudeThreshold = 0.08,
    this.refractoryWindow = const Duration(milliseconds: 250),
    this.spectralMatchThreshold = 0.75,
    this.referenceProfile = defaultShotSpectralProfile,
    this.sampleRate = micSampleRate,
  });

  final double amplitudeThreshold;
  final Duration refractoryWindow;
  final double spectralMatchThreshold;
  final List<double> referenceProfile;

  /// Sample rate (Hz) of the audio chunks fed to [ShotDetector.detect].
  /// Must match the actual capture/clip rate — live capture always uses
  /// [micSampleRate]; recorded-clip evaluation may use a different rate.
  final int sampleRate;
}

/// Detects stick-on-puck shot impacts from a stream of raw PCM16 audio
/// chunks: an amplitude/transient spike that also matches a reference
/// spectral shape, gated by a refractory window so one impact's echo/reverb
/// can't double-count.
class ShotDetector {
  ShotDetector({this.config = const ShotDetectorConfig(), Now now = DateTime.now}) : _now = now;

  final ShotDetectorConfig config;
  final Now _now;
  DateTime? _refractoryUntil;

  /// Feeds one raw PCM16 chunk, in stream order.
  ///
  /// Inputs: [chunk] one raw PCM16 audio buffer.
  /// Outputs: `true` if this chunk was counted as a shot.
  bool detect(Uint8List chunk) {
    final now = _now();
    if (_refractoryUntil != null && now.isBefore(_refractoryUntil!)) {
      return false;
    }

    final amplitude = computeAmplitude(chunk);
    if (amplitude < config.amplitudeThreshold) return false;

    final profile = computeSpectralProfile(chunk, sampleRate: config.sampleRate);
    final similarity = cosineSimilarity(profile, config.referenceProfile);
    if (similarity < config.spectralMatchThreshold) return false;

    _refractoryUntil = now.add(config.refractoryWindow);
    return true;
  }
}
