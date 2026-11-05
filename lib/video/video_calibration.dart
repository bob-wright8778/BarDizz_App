import 'dart:convert';
import 'dart:math' as math;

import 'norm_rect.dart';

/// Where things are in the camera's view, set once per camera placement on
/// the calibration screen. All positions are in the upright frame, i.e.
/// after rotating the raw camera frame by [quarterTurns].
class VideoCalibration {
  const VideoCalibration({
    required this.shootingZone,
    required this.net,
    this.quarterTurns = 0,
    this.puckWidth,
    this.puckHeight,
    this.shotDistanceFeet = defaultShotDistanceFeet,
    this.distanceIsManual = false,
  });

  factory VideoCalibration.fromJson(Map<String, dynamic> json) => VideoCalibration(
        shootingZone: NormRect.fromJson(json['zone'] as Map<String, dynamic>),
        net: NormRect.fromJson(json['net'] as Map<String, dynamic>),
        quarterTurns: (json['turns'] as num?)?.toInt() ?? 0,
        puckWidth: (json['puckW'] as num?)?.toDouble(),
        puckHeight: (json['puckH'] as num?)?.toDouble(),
        shotDistanceFeet: (json['feet'] as num?)?.toDouble() ?? defaultShotDistanceFeet,
        distanceIsManual: json['manual'] as bool? ?? false,
      );

  static VideoCalibration decode(String source) =>
      VideoCalibration.fromJson(jsonDecode(source) as Map<String, dynamic>);

  static const double defaultShotDistanceFeet = 15;

  /// The patch of shooting pad the puck sits on before a shot.
  final NormRect shootingZone;

  /// The net's opening (posts and crossbar) as seen by the camera.
  final NormRect net;

  /// Clockwise quarter turns that make the raw camera frame upright for how
  /// the phone was standing when this was set up.
  final int quarterTurns;

  /// A resting puck's on-screen width and height, both as fractions of frame
  /// width; `null` if no puck was measured. Height is usually well under
  /// width: the camera sees the flat puck at a low angle.
  final double? puckWidth;
  final double? puckHeight;

  /// Distance from the shooting zone to the net, used to turn flight time
  /// into a speed. Estimated from the net's size unless [distanceIsManual].
  final double shotDistanceFeet;
  final bool distanceIsManual;

  /// Outputs: [puckWidth] if measured, otherwise a guess assuming the
  /// shooting zone was drawn about 4 ft wide (a 3 in puck is 1/16 of that).
  double get effectivePuckWidth => puckWidth ?? math.max(shootingZone.width / 16, 0.01);

  /// Outputs: [puckHeight] if measured, otherwise a typical low-angle view of
  /// a puck [effectivePuckWidth] wide.
  double get effectivePuckHeight => puckHeight ?? effectivePuckWidth * 0.6;

  Map<String, dynamic> toJson() => {
        'zone': shootingZone.toJson(),
        'net': net.toJson(),
        'turns': quarterTurns,
        if (puckWidth != null) 'puckW': puckWidth,
        if (puckHeight != null) 'puckH': puckHeight,
        'feet': shotDistanceFeet,
        'manual': distanceIsManual,
      };

  String encode() => jsonEncode(toJson());
}
