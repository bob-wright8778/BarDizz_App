import 'dart:typed_data';

import '../settings/eww_always_bar_down_store.dart';
import 'amplitude.dart';
import 'audio_constants.dart';
import 'classifier_features.dart';
import 'classifier_model.dart';
import 'impact_count.dart';
import 'pcm16.dart';
import 'sound_classifier.dart';

/// Injectable clock, so the refractory window and bar-down confirm window
/// can be tested without real wall-clock delays.
typedef Now = DateTime Function();

/// Injectable classification step returning a [classifierClassLabels]-ordered
/// probability vector, so windowing/refractory/confirm-window mechanics can
/// be tested against a deterministic fake instead of the real 200-tree
/// ensemble. Defaults to [classifySoundProbabilities].
typedef ClassifierFn = List<double> Function(List<double> features);

/// Why the most recent `shot`-labelled window was not reported as a shot.
enum ShotVeto {
  /// The forest's `shot` probability fell below
  /// [ClassifierDetectorConfig.shotMinProbability].
  lowConfidence,

  /// The window held more than [ClassifierDetectorConfig.maxShotImpacts]
  /// distinct impacts -- the signature of stick handling, not one shot.
  tooManyImpacts,
}

/// Injectable toggle read, so the standalone-eww-counts-as-bar-down workaround
/// (card 15) can be flipped live without recreating the detector.
typedef EwwAlwaysBarDownGetter = bool Function();

/// App-level events [ClassifierDetector] reports out of the raw
/// [classifierClassLabels] stream -- `background-quiet`/`stick-handling`
/// classifications, and a `bar-hit` still waiting on its confirming `eww`,
/// report no event (`null`). A standalone `eww` with no pending bar-hit
/// reports no event only when the `ewwAlwaysBarDown` toggle is off; by
/// default it reports [barDown] (card 15).
enum ClassifiedEvent {
  /// A window classified as `shot`.
  shot,

  /// A `bar-hit` window followed by a confirming `eww` window within
  /// [ClassifierDetectorConfig.barDownConfirmWindow].
  barDown,
}

class ClassifierDetectorConfig {
  const ClassifierDetectorConfig({
    // Reused unchanged from the old ShotDetectorConfig/BarDownDetectorConfig
    // amplitude gate -- same real-audio-validated trigger level, now used to
    // open a classification window instead of gating a spectral match
    // directly (see classifier_detector.dart's doc comment / ticket 3).
    this.amplitudeThreshold = 0.08,
    // 800ms: derived from tool/ml_investigation/manifest.csv's trimmed clip
    // durations for the three real single-impact event classes (shot,
    // bar-hit, eww) -- n=64, max observed 0.768s, p95 0.710s, p90 0.668s.
    // Rounded up from the max to a clean number that covers every observed
    // training clip in full with a small margin, so a triggered live window
    // captures the whole impact+decay the model was trained on rather than
    // truncating it. See ticket03-implementation.md for the full stats.
    this.windowDuration = const Duration(milliseconds: 800),
    // Mirrors ShotDetectorConfig/BarDownDetectorConfig's existing 250ms.
    this.refractoryWindow = const Duration(milliseconds: 250),
    // Mirrors the old BarDownDetectorConfig.confirmWindow -- how long after a
    // `bar-hit` classification to keep waiting for a confirming `eww` before
    // silently dropping it.
    this.barDownConfirmWindow = const Duration(seconds: 2),
    this.sampleRate = micSampleRate,
    // The forest's leaves are pure, so a class probability is the fraction
    // of its 200 trees voting for that class. With five classes a plurality
    // win can be as low as ~0.21; requiring an outright majority for `shot`
    // drops the split-vote windows that stick handling tends to produce.
    this.shotMinProbability = 0.5,
    // One shot is one impact, plus possibly the puck striking something loud
    // inside the same 800ms window. Three or more comparable impacts in
    // 800ms is a stick-handling cadence.
    this.maxShotImpacts = 2,
    this.impactCount = const ImpactCountConfig(),
  });

  final double amplitudeThreshold;
  final Duration windowDuration;
  final Duration refractoryWindow;
  final Duration barDownConfirmWindow;

  /// Sample rate (Hz) of the audio chunks fed to [ClassifierDetector.detect].
  final int sampleRate;

  /// Minimum `shot` probability for a `shot`-labelled window to count.
  /// `0.0` disables the gate (plurality label wins, the pre-gate behavior).
  final double shotMinProbability;

  /// Maximum distinct impacts a `shot`-labelled window may hold. Set very
  /// high to disable the veto.
  final int maxShotImpacts;

  /// Envelope tunables for the impact count (see [countImpacts]).
  final ImpactCountConfig impactCount;
}

/// Detects shots and bar-downs from a stream of raw PCM16 audio chunks using
/// the on-device ML classifier (ticket 2): an amplitude-gate trigger opens a
/// fixed-length classification window, the window is classified once via
/// [ClassifierFn], then a refractory period blocks the next trigger. Replaces
/// the old amplitude+spectral-template `ShotDetector`/`BarDownDetector` pair
/// with a single classifier-driven state machine.
///
/// A `shot` classification is reported immediately. A `bar-hit`
/// classification opens a [ClassifierDetectorConfig.barDownConfirmWindow]
/// waiting for a confirming `eww`; that combination reports a bar-down,
/// mirroring the old two-stage `BarDownDetector`'s product semantics (a bar
/// hit alone isn't a notable event -- only one the user audibly reacted to
/// is). `background-quiet`/`stick-handling` report no event. A standalone
/// `eww` with no pending bar-hit reports a bar-down too, by default -- a
/// temporary workaround (card 15) for nets whose bar-hit impact isn't
/// reliably classified; the `ewwAlwaysBarDown` constructor parameter turns
/// this off, restoring the original two-stage-only semantics.
class ClassifierDetector {
  ClassifierDetector({
    this.config = const ClassifierDetectorConfig(),
    Now now = DateTime.now,
    ClassifierFn classify = classifySoundProbabilities,
    EwwAlwaysBarDownGetter ewwAlwaysBarDown = ewwAlwaysBarDownDefaultGetter,
  })  : _now = now,
        _classify = classify,
        _ewwAlwaysBarDown = ewwAlwaysBarDown,
        _targetWindowBytes = _windowByteLength(config);

  final ClassifierDetectorConfig config;
  final Now _now;
  final ClassifierFn _classify;
  final EwwAlwaysBarDownGetter _ewwAlwaysBarDown;
  final int _targetWindowBytes;

  // Sourced from classifierClassLabels by index rather than retyped as
  // literals, so a retrain that renames a class (without reordering it) is
  // picked up automatically instead of silently breaking these comparisons.
  // classifierClassLabels order: background-quiet, bar-hit, eww, shot,
  // stick-handling.
  static final String _barHitLabel = classifierClassLabels[1];
  static final String _ewwLabel = classifierClassLabels[2];
  static const int _shotIndex = 3;
  static final String _shotLabel = classifierClassLabels[_shotIndex];
  static final String _stickHandlingLabel = classifierClassLabels[4];

  DateTime? _refractoryUntil;
  Uint8List? _windowBuffer;
  int _windowFilled = 0;
  DateTime? _barHitConfirmUntil;

  /// The most recently completed window's effective label (one of
  /// [classifierClassLabels]) after the shot gate in [_gateShot], or `null`
  /// before any window has closed -- exposed for tests/diagnostics that want
  /// the underlying label, without changing [detect]'s event-only return
  /// contract. The raw forest output is in [lastProbabilities].
  String? get lastLabel => _lastLabel;
  String? _lastLabel;

  /// The most recently completed window's [classifierClassLabels]-ordered
  /// probability vector, or `null` before any window has closed.
  List<double>? get lastProbabilities => _lastProbabilities;
  List<double>? _lastProbabilities;

  /// Distinct impacts counted in the most recently completed window, or
  /// `null` before any window has closed.
  int? get lastImpactCount => _lastImpactCount;
  int? _lastImpactCount;

  /// Why the most recently completed window's `shot` label was rejected, or
  /// `null` if it was not labelled `shot` or was reported as one.
  ShotVeto? get lastShotVeto => _lastShotVeto;
  ShotVeto? _lastShotVeto;

  static int _windowByteLength(ClassifierDetectorConfig config) {
    final samples = (config.sampleRate * config.windowDuration.inMicroseconds / 1000000).round();
    return samples * 2;
  }

  /// Feeds one raw PCM16 chunk, in stream order.
  ///
  /// Inputs: [chunk] one raw PCM16 audio buffer.
  /// Outputs: the app-level event this chunk's classification (if any just
  /// completed) resolved to, or `null` if no window closed on this chunk, or
  /// the window that closed didn't resolve to a reportable event.
  ClassifiedEvent? detect(Uint8List chunk) {
    final now = _now();
    if (_refractoryUntil != null) {
      if (now.isBefore(_refractoryUntil!)) return null;
      _refractoryUntil = null;
    }

    if (_windowBuffer == null) {
      // Amplitude gate is only re-checked while idle -- a loud chunk arriving
      // mid-window does not restart the window; it simply keeps filling
      // toward the fixed length already in progress (judgment call, see
      // ticket03-implementation.md).
      if (computeAmplitude(chunk) < config.amplitudeThreshold) return null;
      _windowBuffer = Uint8List(_targetWindowBytes);
      _windowFilled = 0;
    }

    final buffer = _windowBuffer!;
    final remaining = _targetWindowBytes - _windowFilled;
    final take = chunk.length < remaining ? chunk.length : remaining;
    buffer.setRange(_windowFilled, _windowFilled + take, chunk);
    _windowFilled += take;
    if (_windowFilled < _targetWindowBytes) return null;

    final samples = decodePcm16(buffer);
    final features = extractClassifierFeaturesFromSamples(samples, sampleRate: config.sampleRate);
    final probabilities = _classify(features);
    final impacts = countImpacts(samples, sampleRate: config.sampleRate, config: config.impactCount);
    final label = _gateShot(argmaxLabel(probabilities, classifierClassLabels), probabilities, impacts);
    _lastLabel = label;
    _lastProbabilities = probabilities;
    _lastImpactCount = impacts;

    _windowBuffer = null;
    _refractoryUntil = now.add(config.refractoryWindow);

    return _resolveEvent(label, now);
  }

  /// Demotes a `shot` label to `stick-handling` when the forest's confidence
  /// is too low or the window holds too many distinct impacts, recording the
  /// reason in [lastShotVeto]. Other labels pass through untouched.
  String _gateShot(String label, List<double> probabilities, int impacts) {
    _lastShotVeto = null;
    if (label != _shotLabel) return label;
    if (probabilities[_shotIndex] < config.shotMinProbability) {
      _lastShotVeto = ShotVeto.lowConfidence;
      return _stickHandlingLabel;
    }
    if (impacts > config.maxShotImpacts) {
      _lastShotVeto = ShotVeto.tooManyImpacts;
      return _stickHandlingLabel;
    }
    return label;
  }

  /// Turns one window's raw [label] into an app-level event, tracking the
  /// bar-hit -> eww confirm window across calls.
  ClassifiedEvent? _resolveEvent(String label, DateTime now) {
    if (_barHitConfirmUntil != null) {
      if (now.isBefore(_barHitConfirmUntil!)) {
        // A window inside an open confirm window is only ever tested as a
        // possible confirming Eww -- a second `bar-hit` here does not reopen
        // or extend the window, matching the old BarDownDetector's
        // "bar-hit detection runs independently from the Eww window it
        // opens" behavior. A `shot` still reports immediately (class doc
        // comment) without disturbing the pending confirm window.
        if (label == _ewwLabel) {
          _barHitConfirmUntil = null;
          return ClassifiedEvent.barDown;
        }
        if (label == _shotLabel) return ClassifiedEvent.shot;
        return null;
      }
      _barHitConfirmUntil = null; // window expired unconfirmed, fall through
    }

    if (label == _barHitLabel) {
      _barHitConfirmUntil = now.add(config.barDownConfirmWindow);
      return null;
    }
    if (label == _shotLabel) return ClassifiedEvent.shot;
    if (label == _ewwLabel && _ewwAlwaysBarDown()) return ClassifiedEvent.barDown;
    return null; // background-quiet, stick-handling, or a standalone eww with the toggle off
  }
}
