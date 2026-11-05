import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:hockey_shot_tracker/video/luma_frame.dart';
import 'package:hockey_shot_tracker/video/shot_fusion.dart';
import 'package:hockey_shot_tracker/video/video_calibration.dart';
import 'package:hockey_shot_tracker/video/video_shot_controller.dart';

/// Stands in for [LiveVideoShotController]'s camera side: no camera, a
/// settable still frame and rotation guess, and analyses pushed by hand.
class FakeVideoShotFeed implements VideoShotFeed {
  FakeVideoShotFeed({this.still, this.suggestedQuarterTurns = 0});

  final StreamController<ShotAnalysis> _analyses = StreamController<ShotAnalysis>.broadcast();
  final ValueNotifier<ShotSource> sourceNotifier = ValueNotifier(ShotSource.soundOnly);

  /// What [captureStill] returns; `null` acts like a stopped camera.
  LumaFrame? still;

  @override
  int suggestedQuarterTurns;

  @override
  VideoCalibration? calibration;

  @override
  Stream<ShotAnalysis> get analyses => _analyses.stream;

  @override
  ValueListenable<ShotSource> get source => sourceNotifier;

  @override
  Future<LumaFrame?> captureStill() async => still;

  @override
  Future<void> setCalibration(VideoCalibration c) async => calibration = c;

  @override
  Widget? buildPreview() => null;

  void emit(ShotAnalysis a) => _analyses.add(a);
}
