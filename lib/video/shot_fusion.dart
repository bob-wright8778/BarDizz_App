import 'shot_tracker.dart';

/// A shot as reported to the session: what the camera saw, plus whether a
/// stick-on-puck sound backed it up.
class ShotAnalysis {
  const ShotAnalysis({required this.video, required this.soundConfirmed});

  final VideoShot video;
  final bool soundConfirmed;
}

class ShotFusionConfig {
  const ShotFusionConfig({
    // Same level as ClassifierDetectorConfig.amplitudeThreshold: loud
    // enough to be a stick or puck impact.
    this.impactAmplitude = 0.08,
    // One impact is a single sharp sound; a ringing chunk run after it is
    // the same impact.
    this.impactDebounce = const Duration(milliseconds: 150),
    // Camera frames and mic chunks reach Dart through different pipelines
    // with tens of milliseconds of different latency each, so match loosely.
    this.confirmWindow = const Duration(milliseconds: 350),
    this.requireSound = true,
  });

  final double impactAmplitude;
  final Duration impactDebounce;
  final Duration confirmWindow;

  /// When `false`, unconfirmed video shots are still reported (with
  /// [ShotAnalysis.soundConfirmed] false), e.g. when the mic is unavailable.
  final bool requireSound;
}

/// Matches camera-detected shots to mic impacts. The camera says *that* the
/// puck left; the sound says a stick actually hit it -- together they reject
/// a puck that was only hidden or kicked away, and a loud noise with no puck
/// movement.
class ShotFusion {
  ShotFusion({this.config = const ShotFusionConfig()});

  final ShotFusionConfig config;
  final List<DateTime> _impacts = [];
  DateTime? _lastLoud;

  /// Inputs: one mic chunk's normalized amplitude and its arrival time, in
  /// order.
  void addAudioLevel(double amplitude, DateTime time) {
    if (amplitude < config.impactAmplitude) return;
    final last = _lastLoud;
    _lastLoud = time;
    if (last != null && time.difference(last) < config.impactDebounce) return;
    _impacts.add(time);
    _impacts.removeWhere((t) => time.difference(t) > const Duration(seconds: 5));
  }

  /// Inputs: a shot the camera finished resolving. Video shots resolve a few
  /// hundred milliseconds after release, so any matching impact has already
  /// been added.
  /// Outputs: the shot to count, or `null` if it needs sound and has none.
  ShotAnalysis? addVideoShot(VideoShot shot) {
    DateTime? match;
    var best = config.confirmWindow;
    for (final t in _impacts) {
      final gap = t.difference(shot.releaseTime).abs();
      if (gap <= best) {
        best = gap;
        match = t;
      }
    }
    if (match != null) _impacts.remove(match);
    if (match == null && config.requireSound) return null;
    return ShotAnalysis(video: shot, soundConfirmed: match != null);
  }
}
