import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/video/norm_rect.dart';
import 'package:hockey_shot_tracker/video/shot_fusion.dart';
import 'package:hockey_shot_tracker/video/shot_tracker.dart';
import 'package:hockey_shot_tracker/video/video_calibration.dart';

final _t0 = DateTime(2026);
DateTime _at(int ms) => _t0.add(Duration(milliseconds: ms));
VideoShot _shotAt(int ms) => VideoShot(releaseTime: _at(ms));

void main() {
  group('ShotFusion', () {
    test('a video shot with a stick impact at release is confirmed', () {
      final fusion = ShotFusion();
      fusion.addAudioLevel(0.3, _at(1020));

      final result = fusion.addVideoShot(_shotAt(1000));

      expect(result, isNotNull);
      expect(result!.soundConfirmed, isTrue);
    });

    test('a video shot with no sound is dropped by default', () {
      final fusion = ShotFusion();
      fusion.addAudioLevel(0.01, _at(1000)); // quiet

      expect(fusion.addVideoShot(_shotAt(1000)), isNull);
    });

    test('an impact well away from the release does not confirm it', () {
      final fusion = ShotFusion();
      fusion.addAudioLevel(0.3, _at(400));

      expect(fusion.addVideoShot(_shotAt(1000)), isNull);
    });

    test('with requireSound off, unconfirmed shots still count but are flagged', () {
      final fusion = ShotFusion(config: const ShotFusionConfig(requireSound: false));

      final result = fusion.addVideoShot(_shotAt(1000));

      expect(result, isNotNull);
      expect(result!.soundConfirmed, isFalse);
    });

    test('one impact confirms only one shot', () {
      final fusion = ShotFusion();
      fusion.addAudioLevel(0.3, _at(1000));

      expect(fusion.addVideoShot(_shotAt(1000)), isNotNull);
      expect(fusion.addVideoShot(_shotAt(1050)), isNull);
    });

    test('a ringing run of loud chunks is a single impact', () {
      final fusion = ShotFusion();
      for (var ms = 1000; ms < 1100; ms += 20) {
        fusion.addAudioLevel(0.3, _at(ms));
      }

      expect(fusion.addVideoShot(_shotAt(1000)), isNotNull);
      expect(fusion.addVideoShot(_shotAt(1080)), isNull);
    });
  });

  group('VideoCalibration', () {
    test('round-trips through its stored form', () {
      const original = VideoCalibration(
        shootingZone: NormRect(0.1, 0.5, 0.4, 0.9),
        net: NormRect(0.5, 0.1, 0.9, 0.4),
        quarterTurns: 1,
        puckWidth: 0.025,
        puckHeight: 0.01,
        shotDistanceFeet: 22,
        distanceIsManual: true,
      );
      final copy = VideoCalibration.decode(original.encode());
      expect(copy.shootingZone, original.shootingZone);
      expect(copy.net, original.net);
      expect(copy.quarterTurns, 1);
      expect(copy.puckWidth, 0.025);
      expect(copy.puckHeight, 0.01);
      expect(copy.shotDistanceFeet, 22);
      expect(copy.distanceIsManual, isTrue);
    });

    test('estimates the puck size from the zone when it was not measured', () {
      const c = VideoCalibration(shootingZone: NormRect(0, 0, 0.32, 0.5), net: NormRect(0, 0, 1, 1));
      expect(c.effectivePuckWidth, closeTo(0.02, 1e-9));
      expect(c.effectivePuckHeight, closeTo(0.012, 1e-9));
    });
  });
}
