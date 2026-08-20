import 'dart:math' as math;
import 'dart:typed_data';

/// Rolling window of raw little-endian PCM16 mono audio, retaining enough
/// history to slice a [preRoll]-before/[postRoll]-after clip around any tap
/// once its post-roll audio has arrived -- see [markTap]/[isReady]/
/// [sliceClip]. Retention is exactly preRoll+postRoll: older audio is
/// evicted on each [append] since no pending tap can ever need it (a tap is
/// finalized the instant its own post-roll arrives).
class RollingClipBuffer {
  RollingClipBuffer({
    required this.sampleRate,
    required Duration preRoll,
    required Duration postRoll,
  })  : _preRollBytes = _toByteCount(preRoll, sampleRate),
        _postRollBytes = _toByteCount(postRoll, sampleRate);

  final int sampleRate;
  final int _preRollBytes;
  final int _postRollBytes;

  final List<int> _bytes = <int>[];
  int _droppedBytes = 0;

  static int _toByteCount(Duration d, int sampleRate) =>
      2 * (d.inMicroseconds * sampleRate / Duration.microsecondsPerSecond).round();

  int get _totalBytes => _droppedBytes + _bytes.length;

  /// Appends a raw PCM16 chunk to the buffer, then evicts anything older
  /// than the retained preRoll+postRoll window.
  void append(Uint8List pcm16Bytes) {
    _bytes.addAll(pcm16Bytes);
    final retain = _preRollBytes + _postRollBytes;
    final excess = _bytes.length - retain;
    if (excess > 0) {
      _bytes.removeRange(0, excess);
      _droppedBytes += excess;
    }
  }

  /// Marks "now" (the most recently appended byte) as a tap event. The
  /// returned index is later passed to [isReady]/[sliceClip].
  int markTap() => _totalBytes;

  /// True once postRoll worth of audio has arrived after [tapByteIndex].
  bool isReady(int tapByteIndex) => _totalBytes >= tapByteIndex + _postRollBytes;

  /// Slices the clip around [tapByteIndex]: preRoll bytes before it up to
  /// postRoll bytes after. Either side is silently truncated instead of
  /// erroring if the buffer doesn't have that much data yet (a Stop-flushed
  /// clip) or any more (audio already evicted past the retention window).
  Uint8List sliceClip(int tapByteIndex) {
    final start = math.max(tapByteIndex - _preRollBytes, _droppedBytes);
    final end = math.min(tapByteIndex + _postRollBytes, _totalBytes);
    final startIdx = start - _droppedBytes;
    final endIdx = math.max(end - _droppedBytes, startIdx);
    return Uint8List.fromList(_bytes.sublist(startIdx, endIdx));
  }
}
