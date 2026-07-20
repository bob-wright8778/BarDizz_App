import 'dart:typed_data';

import 'amplitude.dart';
import 'audio_constants.dart';
import 'classifier_features.dart';
import 'sound_classifier.dart';

/// Injectable clock, so the refractory window and bar-down confirm window
/// can be tested without real wall-clock delays.
typedef Now = DateTime Function();

/// Injectable classification step, so windowing/refractory/confirm-window
/// mechanics can be tested against a deterministic fake instead of the real
/// 200-tree ensemble. Defaults to [classifySound].
typedef ClassifierFn = String Function(List<double> features);

/// App-level events [ClassifierDetector] reports out of the raw
/// [classifierClassLabels] stream -- `background-quiet`/`stick-handling`
/// classifications, a standalone `eww` with no pending bar-hit, and a
/// `bar-hit` still waiting on its confirming `eww` all report no event
/// (`null`).
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
  });

  final double amplitudeThreshold;
  final Duration windowDuration;
  final Duration refractoryWindow;
  final Duration barDownConfirmWindow;

  /// Sample rate (Hz) of the audio chunks fed to [ClassifierDetector.detect].
  final int sampleRate;
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
/// waiting for a confirming `eww`; only that combination reports a bar-down,
/// mirroring the old two-stage `BarDownDetector`'s product semantics (a bar
/// hit alone isn't a notable event -- only one the user audibly reacted to
/// is). `background-quiet`/`stick-handling`, and a standalone `eww` with no
/// pending bar-hit, report no event.
class ClassifierDetector {
  ClassifierDetector({
    this.config = const ClassifierDetectorConfig(),
    Now now = DateTime.now,
    ClassifierFn classify = classifySound,
  })  : _now = now,
        _classify = classify,
        _targetWindowBytes = _windowByteLength(config);

  final ClassifierDetectorConfig config;
  final Now _now;
  final ClassifierFn _classify;
  final int _targetWindowBytes;

  DateTime? _refractoryUntil;
  Uint8List? _windowBuffer;
  int _windowFilled = 0;
  DateTime? _barHitConfirmUntil;

  /// The most recently completed window's raw classifier label (one of
  /// [classifierClassLabels]), or `null` before any window has closed --
  /// exposed for tests/diagnostics that want the underlying label, without
  /// changing [detect]'s event-only return contract.
  String? get lastLabel => _lastLabel;
  String? _lastLabel;

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

    final features = extractClassifierFeatures(buffer, sampleRate: config.sampleRate);
    final label = _classify(features);
    _lastLabel = label;

    _windowBuffer = null;
    _refractoryUntil = now.add(config.refractoryWindow);

    return _resolveEvent(label, now);
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
        if (label == 'eww') {
          _barHitConfirmUntil = null;
          return ClassifiedEvent.barDown;
        }
        if (label == 'shot') return ClassifiedEvent.shot;
        return null;
      }
      _barHitConfirmUntil = null; // window expired unconfirmed, fall through
    }

    if (label == 'bar-hit') {
      _barHitConfirmUntil = now.add(config.barDownConfirmWindow);
      return null;
    }
    if (label == 'shot') return ClassifiedEvent.shot;
    return null; // background-quiet, stick-handling, or a standalone eww
  }
}
