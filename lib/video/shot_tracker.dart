import 'dart:math' as math;

import 'luma_frame.dart';
import 'puck_finder.dart';
import 'video_calibration.dart';

const double _feetPerSecondPerMph = 5280 / 3600;

/// Where a shot reached the net, as fractions of the net opening:
/// x 0 = left post, 1 = right post; y 0 = crossbar, 1 = ice.
class NetHit {
  const NetHit(this.x, this.y);

  final double x;
  final double y;

  static const _rows = ['Top', 'Middle', 'Low'];
  static const _cols = ['left', 'centre', 'right'];

  /// Outputs: a 3x3 target label from the camera's point of view, e.g.
  /// "Top left".
  String get zoneLabel {
    int third(double v) => (v.clamp(0.0, 0.999) * 3).floor();
    return '${_rows[third(y)]} ${_cols[third(x)]}';
  }
}

/// One shot seen on camera: the puck left the shooting zone too fast to
/// follow and did not come back.
class VideoShot {
  const VideoShot({required this.releaseTime, this.flightTime, this.speedMph, this.netHit});

  final DateTime releaseTime;

  /// Release to first movement at the net; `null` if nothing moved there.
  final Duration? flightTime;

  /// [VideoCalibration.shotDistanceFeet] over [flightTime]; `null` without a
  /// plausible flight time.
  final double? speedMph;

  final NetHit? netHit;
}

class ShotTrackerConfig {
  const ShotTrackerConfig({
    this.finder = const PuckFinderConfig(),
    // Frames without a puck before it counts as gone. A hard shot blurs the
    // puck out of existence on the very next frame; two frames rides out a
    // single dropped detection.
    this.missingFrames = 2,
    // The puck must have been sitting in the zone for at least this many
    // frames within [presenceWindow] before vanishing, so a puck rolling
    // through the zone, or a one-frame false blob, never reads as a shot.
    this.minPresentFrames = 5,
    this.presenceWindow = const Duration(seconds: 1),
    // A puck that reappears this soon was hidden (stick blade, skate), not
    // shot. Also the minimum delay before a shot is reported.
    this.reappearWindow = const Duration(milliseconds: 400),
    // How long after release to keep watching the net for the puck.
    this.netWindow = const Duration(milliseconds: 1500),
    // How far outside the zone (in puck diameters) a puck is still followed,
    // so one nudged off the edge is tracked rather than read as vanished.
    this.zoneMarginPucks = 2.0,
    // Per-cell brightness change between frames that counts as movement.
    this.motionDelta = 30,
    // Moving cells inside the net needed to call an arrival, in puck areas.
    // Half a puck: a blurred puck or a mesh ripple only partly changes cells.
    this.minMotionPucks = 0.5,
    // Above this fraction of the net moving at once, it is a lighting or
    // exposure jump, not a puck.
    this.maxMotionFraction = 0.6,
    this.minSpeedMph = 10,
    this.maxSpeedMph = 130,
  });

  final PuckFinderConfig finder;
  final int missingFrames;
  final int minPresentFrames;
  final Duration presenceWindow;
  final Duration reappearWindow;
  final Duration netWindow;
  final double zoneMarginPucks;
  final int motionDelta;
  final double minMotionPucks;
  final double maxMotionFraction;
  final double minSpeedMph;
  final double maxSpeedMph;
}

/// Turns a stream of analysis-grid frames into [VideoShot]s.
///
/// A shot is a puck that sat in the shooting zone, vanished (a released
/// puck blurs out of a 30-60 fps frame almost instantly), and did not
/// reappear within [ShotTrackerConfig.reappearWindow]. After release it
/// watches the net rectangle for the first burst of movement -- the puck
/// arriving or the mesh kicking -- to estimate flight time, speed and where
/// the shot went.
class ShotTracker {
  ShotTracker(this.calibration, {this.config = const ShotTrackerConfig()});

  final VideoCalibration calibration;
  final ShotTrackerConfig config;

  LumaFrame? _prevFrame;
  DateTime? _prevTime;

  PuckBlob? _lastPuck;
  DateTime? _lastPuckTime;
  bool _lastPuckInZone = false;
  int _missing = 0;
  DateTime? _firstMissingTime;
  final List<DateTime> _sightings = [];

  _PendingShot? _pending;

  /// The puck found on the most recent frame, or `null` -- for the live
  /// overlay.
  PuckBlob? get currentPuck => _missing == 0 ? _lastPuck : null;

  /// Inputs: the next [frame] and when it was captured, in order.
  /// Outputs: a finished [VideoShot] if one resolved on this frame.
  VideoShot? addFrame(LumaFrame frame, DateTime time) {
    final prev = _prevFrame;
    final prevTime = _prevTime;
    _prevFrame = frame;
    _prevTime = time;

    final diameter = calibration.effectivePuckDiameter;
    final expectedArea = expectedPuckArea(frame, diameter);
    final reference = medianLuma(frame, calibration.shootingZone);
    final aspect = frame.width / frame.height;
    final search = calibration.shootingZone
        .inflate(diameter * config.zoneMarginPucks, diameter * config.zoneMarginPucks * aspect);
    final blob = _pick(findPuckBlobs(
      frame,
      search,
      referenceLuma: reference,
      expectedArea: expectedArea,
      config: config.finder,
    ));

    final pending = _pending;
    if (pending != null) {
      final sinceRelease = time.difference(pending.releaseTime);
      if (blob != null && sinceRelease <= config.reappearWindow) {
        // Only hidden, not shot.
        _pending = null;
        _see(blob, time);
        return null;
      }
      if (pending.arrival == null && prev != null && prevTime != null) {
        _watchNet(pending, prev, frame, prevTime, time, expectedArea);
      }
      if (blob != null) _see(blob, time);
      final netDone = pending.arrival != null || sinceRelease >= config.netWindow;
      if (sinceRelease >= config.reappearWindow && netDone) {
        _pending = null;
        return _finish(pending);
      }
      return null;
    }

    if (blob != null) {
      _see(blob, time);
      return null;
    }

    _missing++;
    final last = _lastPuck;
    final lastTime = _lastPuckTime;
    if (_missing == 1) _firstMissingTime = time;
    if (_missing < config.missingFrames || last == null || lastTime == null) return null;

    _sightings.removeWhere((t) => lastTime.difference(t) > config.presenceWindow);
    final settled = _lastPuckInZone && _sightings.length >= config.minPresentFrames;
    _lastPuck = null;
    _lastPuckTime = null;
    _sightings.clear();
    if (settled) {
      _pending = _PendingShot(_midpoint(lastTime, _firstMissingTime ?? time));
    }
    return null;
  }

  PuckBlob? _pick(List<PuckBlob> blobs) {
    if (blobs.isEmpty) return null;
    final last = _lastPuck;
    if (last != null) {
      double d(PuckBlob b) {
        final dx = b.x - last.x;
        final dy = b.y - last.y;
        return dx * dx + dy * dy;
      }

      return blobs.reduce((a, b) => d(a) <= d(b) ? a : b);
    }
    return blobs.reduce((a, b) => a.area >= b.area ? a : b);
  }

  void _see(PuckBlob blob, DateTime time) {
    _lastPuck = blob;
    _lastPuckTime = time;
    _missing = 0;
    _lastPuckInZone = calibration.shootingZone.contains(blob.x, blob.y);
    if (_lastPuckInZone) _sightings.add(time);
  }

  void _watchNet(
    _PendingShot pending,
    LumaFrame prev,
    LumaFrame frame,
    DateTime prevTime,
    DateTime time,
    double puckArea,
  ) {
    if (prev.width != frame.width || prev.height != frame.height) return;
    final minFlight = Duration(
      microseconds:
          (calibration.shotDistanceFeet / (config.maxSpeedMph * _feetPerSecondPerMph) * 1e6).round(),
    );
    if (time.difference(pending.releaseTime) < minFlight) return;

    final net = calibration.net;
    final x0 = (net.left * frame.width).floor().clamp(0, frame.width - 1);
    final y0 = (net.top * frame.height).floor().clamp(0, frame.height - 1);
    final x1 = (net.right * frame.width).ceil().clamp(0, frame.width - 1);
    final y1 = (net.bottom * frame.height).ceil().clamp(0, frame.height - 1);
    var moving = 0;
    var sumX = 0.0;
    var sumY = 0.0;
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        if ((frame.at(x, y) - prev.at(x, y)).abs() >= config.motionDelta) {
          moving++;
          sumX += x + 0.5;
          sumY += y + 0.5;
        }
      }
    }
    final cells = (x1 - x0 + 1) * (y1 - y0 + 1);
    if (moving < math.max(2, puckArea * config.minMotionPucks)) return;
    if (moving > cells * config.maxMotionFraction) return;

    final hitX = (sumX / moving / frame.width - net.left) / net.width;
    final hitY = (sumY / moving / frame.height - net.top) / net.height;
    pending.arrival = _midpoint(prevTime, time);
    pending.hit = NetHit(hitX.clamp(0.0, 1.0), hitY.clamp(0.0, 1.0));
  }

  VideoShot _finish(_PendingShot pending) {
    final arrival = pending.arrival;
    if (arrival == null) return VideoShot(releaseTime: pending.releaseTime);
    final flight = arrival.difference(pending.releaseTime);
    final seconds = flight.inMicroseconds / 1e6;
    final mph = calibration.shotDistanceFeet / seconds / _feetPerSecondPerMph;
    if (mph < config.minSpeedMph || mph > config.maxSpeedMph) {
      // Too slow to be this puck: whatever moved at the net was something else.
      return VideoShot(releaseTime: pending.releaseTime);
    }
    return VideoShot(
      releaseTime: pending.releaseTime,
      flightTime: flight,
      speedMph: mph,
      netHit: pending.hit,
    );
  }

  static DateTime _midpoint(DateTime a, DateTime b) =>
      a.add(Duration(microseconds: b.difference(a).inMicroseconds ~/ 2));
}

class _PendingShot {
  _PendingShot(this.releaseTime);

  final DateTime releaseTime;
  DateTime? arrival;
  NetHit? hit;
}
