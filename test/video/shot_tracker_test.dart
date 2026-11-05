import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/video/luma_frame.dart';
import 'package:hockey_shot_tracker/video/shot_tracker.dart';

import 'synthetic_frames.dart';

const _frameGap = Duration(microseconds: 33333); // 30 fps

/// Feeds frames to a tracker at 30 fps and collects any shots.
class _Feeder {
  _Feeder() : tracker = ShotTracker(testCalibration);

  final ShotTracker tracker;
  DateTime now = DateTime(2026);
  final shots = <VideoShot>[];

  void feed(LumaFrame frame, {int times = 1}) {
    for (var i = 0; i < times; i++) {
      final shot = tracker.addFrame(frame, now);
      if (shot != null) shots.add(shot);
      now = now.add(_frameGap);
    }
  }
}

final _restingPuck = syntheticFrame(discs: [(0.5, 0.75, 0.03)]);
final _empty = syntheticFrame();
// The puck (or the mesh it kicks) showing up high on the left of the net.
final _puckTopLeftOfNet = syntheticFrame(discs: [(0.44, 0.14, 0.03)]);

void main() {
  test('a settled puck that vanishes and reaches the net is a shot with speed and target', () {
    final f = _Feeder();
    f.feed(_restingPuck, times: 10);
    final releaseAround = f.now;
    f.feed(_empty, times: 4); // ~130ms of flight
    f.feed(_puckTopLeftOfNet);
    f.feed(_empty, times: 12); // past the reappear window

    expect(f.shots, hasLength(1));
    final shot = f.shots.single;
    expect(shot.releaseTime.difference(releaseAround).inMilliseconds.abs(), lessThan(40));
    expect(shot.flightTime, isNotNull);
    // 15 ft in ~0.15s is ~68 mph; frame timing makes this coarse.
    expect(shot.speedMph, inInclusiveRange(50, 90));
    expect(shot.netHit!.zoneLabel, 'Top left');
  });

  test('a puck that reappears quickly was only hidden by the stick, not shot', () {
    final f = _Feeder();
    f.feed(_restingPuck, times: 10);
    f.feed(_empty, times: 5); // ~170ms behind the blade
    f.feed(_restingPuck, times: 30);

    expect(f.shots, isEmpty);
  });

  test('a puck seen for only a couple of frames is not settled enough to count', () {
    final f = _Feeder();
    f.feed(_restingPuck, times: 2);
    f.feed(_empty, times: 60);

    expect(f.shots, isEmpty);
  });

  test('a shot that never shows at the net is still reported, without speed or target', () {
    final f = _Feeder();
    f.feed(_restingPuck, times: 10);
    f.feed(_empty, times: 60); // 2s: past the 1.5s net window

    expect(f.shots, hasLength(1));
    expect(f.shots.single.speedMph, isNull);
    expect(f.shots.single.netHit, isNull);
  });

  test('movement at the net too soon after release to be the puck is ignored', () {
    final f = _Feeder();
    f.feed(_restingPuck, times: 10);
    f.feed(_empty, times: 2);
    // Shooter's follow-through crossing the net ~50ms after release: faster than any shot.
    f.feed(_puckTopLeftOfNet);
    f.feed(_empty, times: 60);

    expect(f.shots, hasLength(1));
    expect(f.shots.single.speedMph, isNull);
  });

  test('a puck stickhandled around the zone is followed, never counted', () {
    final f = _Feeder();
    for (var i = 0; i < 40; i++) {
      final x = 0.42 + (i % 10) * 0.015;
      f.feed(syntheticFrame(discs: [(x, 0.75, 0.03)]));
    }
    expect(f.shots, isEmpty);
  });

  test('two shots in a row are both counted', () {
    final f = _Feeder();
    for (var shot = 0; shot < 2; shot++) {
      f.feed(_restingPuck, times: 10);
      f.feed(_empty, times: 4);
      f.feed(_puckTopLeftOfNet);
      f.feed(_empty, times: 12);
    }
    expect(f.shots, hasLength(2));
  });

  group('NetHit.zoneLabel', () {
    test('splits the net into a 3x3 grid from the camera view', () {
      expect(const NetHit(0.1, 0.1).zoneLabel, 'Top left');
      expect(const NetHit(0.5, 0.5).zoneLabel, 'Middle centre');
      expect(const NetHit(0.9, 1.0).zoneLabel, 'Low right');
    });
  });
}
