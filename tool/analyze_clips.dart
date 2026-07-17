// ignore_for_file: avoid_print
// Data-gathering harness for shot-detector threshold/feature tuning: dumps
// per-transient amplitude, spectral similarity, and decay time for every
// clip in a directory, so real thresholds can be picked from evidence
// instead of guessed.
//
// Usage:
//   dart run tool/analyze_clips.dart <clips-dir>
//
// Directory should contain 16-bit PCM WAV clips (mono or stereo, any sample
// rate).
import 'dart:io';

import 'package:hockey_shot_tracker/audio/amplitude.dart';
import 'package:hockey_shot_tracker/audio/shot_detector.dart';
import 'package:hockey_shot_tracker/audio/spectral_profile.dart';
import 'package:hockey_shot_tracker/audio/wav_chunker.dart';
import 'package:hockey_shot_tracker/audio/wav_reader.dart';

import 'cli_helpers.dart';

// Today's production ShotDetectorConfig.amplitudeThreshold, read from the
// actual default rather than copied, so this stays correct if that default
// is ever retuned.
final _ampGate = const ShotDetectorConfig().amplitudeThreshold;

void main(List<String> args) {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/analyze_clips.dart <clips-dir>');
    exitCode = 64;
    return;
  }

  final dir = requireDirectory(args[0]);
  if (dir == null) return;

  for (final file in listWavFiles(dir)) {
    final wav = readWav(file.readAsBytesSync());
    _analyzeClip(file.path, wav);
  }
}

void _analyzeClip(String path, WavAudio wav) {
  final chunks = chunkWav(wav);
  final peakIdx = peakChunkIndex(chunks);
  if (peakIdx == -1) {
    print('=== $path: empty clip, skipped ===\n');
    return;
  }
  final amplitudes = chunks.map(computeAmplitude).toList();
  final chunkMs = defaultChunkSampleCount * 1000 / wav.sampleRate;

  print('=== $path (${chunks.length} chunks, ${chunkMs.toStringAsFixed(1)}ms each) ===');

  final peakProfile = computeSpectralProfile(chunks[peakIdx], sampleRate: wav.sampleRate);
  final peakSim = cosineSimilarity(peakProfile, defaultShotSpectralProfile);
  final peakDecay = _decayTimeMs(amplitudes, peakIdx, chunkMs);
  print(
    '  GLOBAL PEAK: chunk $peakIdx  amp=${amplitudes[peakIdx].toStringAsFixed(3)}  '
    'spectralSim=${peakSim.toStringAsFixed(3)}  decayToHalf=${peakDecay.toStringAsFixed(0)}ms',
  );

  print('  All local peaks >= $_ampGate amplitude (today\'s production gate):');
  for (var i = 0; i < amplitudes.length; i++) {
    final isLocalPeak = amplitudes[i] >= _ampGate &&
        (i == 0 || amplitudes[i] >= amplitudes[i - 1]) &&
        (i == amplitudes.length - 1 || amplitudes[i] >= amplitudes[i + 1]);
    if (!isLocalPeak) continue;
    final sim = i == peakIdx
        ? peakSim
        : cosineSimilarity(
            computeSpectralProfile(chunks[i], sampleRate: wav.sampleRate),
            defaultShotSpectralProfile,
          );
    final decay = _decayTimeMs(amplitudes, i, chunkMs);
    final tag = i == peakIdx ? '  <-- global peak' : '';
    print(
      '    chunk $i  amp=${amplitudes[i].toStringAsFixed(3)}  '
      'spectralSim=${sim.toStringAsFixed(3)}  decayToHalf=${decay.toStringAsFixed(0)}ms$tag',
    );
  }
  print('');
}

/// Time from [peakIdx] until amplitude first drops to half the peak value,
/// walking forward chunk by chunk. Returns the clip's remaining duration if
/// it never decays that far before the clip ends.
double _decayTimeMs(List<double> amplitudes, int peakIdx, double chunkMs) {
  final halfPeak = amplitudes[peakIdx] / 2;
  for (var i = peakIdx + 1; i < amplitudes.length; i++) {
    if (amplitudes[i] <= halfPeak) return (i - peakIdx) * chunkMs;
  }
  return (amplitudes.length - 1 - peakIdx) * chunkMs;
}
