import 'dart:math' as math;
import 'dart:typed_data';

import 'audio_constants.dart';
import 'shot_detector.dart' show Now;
import 'spectral_profile.dart';

class BarDownDetectorConfig {
  const BarDownDetectorConfig({
    required this.ewwReferenceProfile,
    this.barHitAmplitudeThreshold = 0.08,
    this.barHitSpectralMatchThreshold = 0.75,
    this.barHitReferenceProfile = defaultBarHitSpectralProfile,
    this.ewwAmplitudeThreshold = 0.08,
    this.ewwSpectralMatchThreshold = 0.75,
    this.confirmWindow = const Duration(seconds: 2),
    this.refractoryWindow = const Duration(milliseconds: 250),
    this.sampleRate = micSampleRate,
  });

  /// Per-user calibrated "Eww" profile -- unlike [barHitReferenceProfile]
  /// there is no fixed default, since the Eww match is what actually decides
  /// whether a bar down counts (see `dev/stages/01-planning/output/spec.md`
  /// decision 2); always supplied by the caller.
  final List<double> ewwReferenceProfile;

  final double barHitAmplitudeThreshold;
  final double barHitSpectralMatchThreshold;
  final List<double> barHitReferenceProfile;

  final double ewwAmplitudeThreshold;
  final double ewwSpectralMatchThreshold;

  /// How long after a bar-hit impact to keep listening for a confirming Eww.
  final Duration confirmWindow;

  /// How long after a confirmed bar down to ignore further bar-hit/Eww
  /// matches, so echo/reverb from the Eww itself (or the impact) can't
  /// double-count the same physical event -- mirrors
  /// [ShotDetectorConfig.refractoryWindow].
  final Duration refractoryWindow;

  /// Sample rate (Hz) of the audio chunks fed to [BarDownDetector.detect].
  final int sampleRate;
}

/// Detects a "bar down": a bar/crossbar impact (stage 1) followed within
/// [BarDownDetectorConfig.confirmWindow] by a confirming "Eww" (stage 2). A
/// bar-hit with no Eww in the window is silently dropped. Mirrors
/// [ShotDetector]'s amplitude+spectral matching but composes two profile
/// matches with timing between them instead of one.
class BarDownDetector {
  BarDownDetector({required this.config, Now now = DateTime.now}) : _now = now;

  final BarDownDetectorConfig config;
  final Now _now;
  DateTime? _windowUntil;
  DateTime? _refractoryUntil;

  /// Feeds one raw PCM16 chunk, in stream order.
  ///
  /// Inputs: [chunk] one raw PCM16 audio buffer.
  /// Outputs: `true` if this chunk completed a bar down (a confirming Eww
  /// matched inside the window opened by an earlier bar-hit).
  bool detect(Uint8List chunk) {
    final features = computeChunkFeatures(
      chunk,
      amplitudeThreshold: math.min(config.barHitAmplitudeThreshold, config.ewwAmplitudeThreshold),
      sampleRate: config.sampleRate,
    );
    return detectFromFeatures(features.amplitude, features.profile);
  }

  /// Same as [detect], but takes a chunk's amplitude/spectral profile
  /// already computed by the caller -- lets a caller feeding the same chunk
  /// to more than one detector compute those once and share them, instead
  /// of each detector redoing the analysis.
  ///
  /// Inputs: [amplitude]/[profile] the chunk's precomputed features.
  /// Outputs: `true` if this chunk completed a bar down.
  bool detectFromFeatures(double amplitude, List<double> profile) {
    final now = _now();

    if (_refractoryUntil != null) {
      if (now.isBefore(_refractoryUntil!)) return false;
      _refractoryUntil = null;
    }

    if (_windowUntil != null) {
      if (now.isBefore(_windowUntil!)) {
        final isEww = matchesProfile(
          amplitude,
          profile,
          amplitudeThreshold: config.ewwAmplitudeThreshold,
          spectralMatchThreshold: config.ewwSpectralMatchThreshold,
          referenceProfile: config.ewwReferenceProfile,
        );
        if (isEww) {
          _windowUntil = null;
          _refractoryUntil = now.add(config.refractoryWindow);
        }
        return isEww;
      }
      _windowUntil = null;
    }

    final isBarHit = matchesProfile(
      amplitude,
      profile,
      amplitudeThreshold: config.barHitAmplitudeThreshold,
      spectralMatchThreshold: config.barHitSpectralMatchThreshold,
      referenceProfile: config.barHitReferenceProfile,
    );
    if (isBarHit) _windowUntil = now.add(config.confirmWindow);
    return false;
  }
}
