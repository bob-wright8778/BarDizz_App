import 'dart:math' as math;
import 'dart:typed_data';

import 'amplitude.dart';
import 'audio_constants.dart';

/// Center frequencies (Hz) of the bands used for the spectral shape profile.
/// Spans the impulsive, broadband "crack" of a stick-puck impact at 16kHz
/// sample rate (Nyquist 8kHz).
const List<double> spectralBandCenters = [500, 1000, 2000, 3000, 4000, 6000];

/// Reference profile for a stick-on-puck impact's frequency shape
/// (normalized relative energy per band in [spectralBandCenters]), derived
/// from 43 real shot recordings on 2026-07-17 (`tool/derive_profile.dart`,
/// averaging each clip's peak-amplitude chunk's spectral profile via
/// [deriveReferenceProfile] — same math as per-user calibration). Real shots
/// through this mic pipeline read as low-frequency-dominant, not the
/// high-frequency "crack" a prior hand-picked placeholder assumed — that
/// placeholder scored real shots at 0.12-0.30 similarity, well under the
/// detection threshold. Not reachable in production live detection —
/// `AppHomeGate` (`main.dart`) requires a per-user calibration profile to
/// exist before the session screen is ever shown, so
/// `LiveMicLevelController` always passes a calibrated `referenceProfile`
/// (`mic_level_controller.dart`). This constant is the default `ShotDetector`
/// falls back to when none is supplied — used by tests and the tuning tools.
const List<double> defaultShotSpectralProfile = [0.5121, 0.3161, 0.0727, 0.0588, 0.0183, 0.0220];

/// Reference profile for a bar/crossbar impact's frequency shape, derived the
/// same way as [defaultShotSpectralProfile] (`tool/derive_profile.dart`) from
/// the 6 real bar-hit clips in `Bar only/` and `BAr and EWW/`
/// (`G:\Source\Repos\HockeyShotAudio`) — for the latter, each clip's
/// peak-amplitude chunk (same [deriveReferenceProfile] math) was verified to
/// land on the bar impact itself, not the following "Eww" (0.96-0.98 cosine
/// similarity to the impact-shaped [defaultShotSpectralProfile], versus a
/// vocal reaction's very different spectral shape), so no manual trimming was
/// needed. Small sample (n=6) versus [defaultShotSpectralProfile]'s n=43 —
/// see `dev/contexts/hockey-shot-tracker.md` in AI_Workspace.
const List<double> defaultBarHitSpectralProfile = [0.6027, 0.2605, 0.0644, 0.0464, 0.0208, 0.0052];

/// Computes a normalized per-band energy "shape" profile of a PCM16 buffer
/// via the Goertzel algorithm, one energy value per entry in
/// [spectralBandCenters].
///
/// Inputs: [pcm16Bytes] raw PCM16 audio bytes; [sampleRate] the capture
/// sample rate (Hz).
/// Outputs: a [spectralBandCenters]-length list of relative band energies
/// summing to 1.0 (all zero if the input is silent/too short).
List<double> computeSpectralProfile(Uint8List pcm16Bytes, {int sampleRate = micSampleRate}) {
  final sampleCount = pcm16Bytes.length ~/ 2;
  if (sampleCount == 0) return List.filled(spectralBandCenters.length, 0.0);

  final byteData = ByteData.sublistView(pcm16Bytes, 0, sampleCount * 2);
  final samples = List<double>.generate(
    sampleCount,
    (i) => byteData.getInt16(i * 2, Endian.little) / 32768.0,
  );

  final energies = spectralBandCenters
      .map((freq) => _goertzelEnergy(samples, sampleRate, freq))
      .toList();

  final total = energies.fold<double>(0.0, (sum, e) => sum + e);
  if (total <= 0) return List.filled(spectralBandCenters.length, 0.0);
  return energies.map((e) => e / total).toList();
}

/// Single-frequency energy via the Goertzel algorithm — cheaper than a full
/// FFT when only a handful of target frequencies are needed.
double _goertzelEnergy(List<double> samples, int sampleRate, double targetFreq) {
  final n = samples.length;
  final k = (0.5 + n * targetFreq / sampleRate).floor();
  final omega = (2 * math.pi * k) / n;
  final coeff = 2 * math.cos(omega);

  var s1 = 0.0;
  var s2 = 0.0;
  for (final sample in samples) {
    final s0 = sample + coeff * s1 - s2;
    s2 = s1;
    s1 = s0;
  }
  final energy = s1 * s1 + s2 * s2 - coeff * s1 * s2;
  return energy < 0 ? 0.0 : energy;
}

/// Computes a chunk's amplitude, and its spectral profile only if the
/// amplitude clears [amplitudeThreshold] -- skips the profile's Goertzel
/// passes entirely for chunks no detector could match anyway. Shared by
/// [ShotDetector.detect], [BarDownDetector.detect], and
/// [LiveMicLevelController]'s combined per-chunk dispatch, so each stops
/// duplicating the same amplitude-then-profile gate inline.
///
/// Inputs: [chunk] raw PCM16 audio; [amplitudeThreshold] the gate below
/// which the profile isn't computed; [sampleRate] the capture rate.
/// Outputs: the chunk's amplitude, and its spectral profile (or `const []`
/// if the amplitude didn't clear the gate).
({double amplitude, List<double> profile}) computeChunkFeatures(
  Uint8List chunk, {
  required double amplitudeThreshold,
  required int sampleRate,
}) {
  final amplitude = computeAmplitude(chunk);
  final profile = amplitude < amplitudeThreshold
      ? const <double>[]
      : computeSpectralProfile(chunk, sampleRate: sampleRate);
  return (amplitude: amplitude, profile: profile);
}

/// Shared amplitude-gate + spectral-shape match used by both [ShotDetector]
/// and [BarDownDetector] so their matching rule can't drift apart.
///
/// Inputs: [amplitude]/[profile] a chunk's precomputed features; the
/// threshold/reference pair to test them against.
/// Outputs: whether the chunk clears the amplitude gate and matches
/// [referenceProfile] closely enough.
bool matchesProfile(
  double amplitude,
  List<double> profile, {
  required double amplitudeThreshold,
  required double spectralMatchThreshold,
  required List<double> referenceProfile,
}) {
  if (amplitude < amplitudeThreshold) return false;
  return cosineSimilarity(profile, referenceProfile) >= spectralMatchThreshold;
}

/// Cosine similarity between two equal-length vectors, in [0.0, 1.0] for the
/// non-negative energy profiles this is used with. Returns 0.0 rather than
/// dividing by zero if either vector is all-zero.
double cosineSimilarity(List<double> a, List<double> b) {
  assert(a.length == b.length);
  var dot = 0.0;
  var normA = 0.0;
  var normB = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    normA += a[i] * a[i];
    normB += b[i] * b[i];
  }
  if (normA == 0 || normB == 0) return 0.0;
  return dot / (math.sqrt(normA) * math.sqrt(normB));
}
