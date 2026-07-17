/// Sample rate (Hz) for raw PCM capture. 16kHz mono is enough headroom for
/// an impulsive stick/puck transient while keeping buffers small.
///
/// Deliberately free of any Flutter dependency (unlike [MicCaptureService]),
/// so the pure-Dart detection engine (`shot_detector.dart`,
/// `spectral_profile.dart`, `clip_evaluator.dart`) can be exercised by a
/// plain `dart run` CLI tool without pulling in `dart:ui`.
const int micSampleRate = 16000;
