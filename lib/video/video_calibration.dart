import 'dart:convert';
import 'dart:math' as math;

import 'norm_rect.dart';

/// Where things are in the camera's view, set once per camera placement on
/// the calibration screen.
class VideoCalibration {
  const VideoCalibration({
    required this.shootingZone,
    required this.net,
    this.puckDiameter,
    this.shotDistanceFeet = defaultShotDistanceFeet,
  });

  factory VideoCalibration.fromJson(Map<String, dynamic> json) => VideoCalibration(
        shootingZone: NormRect.fromJson(json['zone'] as Map<String, dynamic>),
        net: NormRect.fromJson(json['net'] as Map<String, dynamic>),
        puckDiameter: (json['puck'] as num?)?.toDouble(),
        shotDistanceFeet: (json['feet'] as num?)?.toDouble() ?? defaultShotDistanceFeet,
      );

  static VideoCalibration decode(String source) =>
      VideoCalibration.fromJson(jsonDecode(source) as Map<String, dynamic>);

  static const double defaultShotDistanceFeet = 15;

  /// The patch of shooting pad the puck sits on before a shot.
  final NormRect shootingZone;

  /// The net's opening (posts and crossbar) as seen by the camera.
  final NormRect net;

  /// A resting puck's diameter as a fraction of frame width, measured on the
  /// calibration screen; `null` falls back to [effectivePuckDiameter]'s
  /// estimate from the zone size.
  final double? puckDiameter;

  /// Real distance from the shooting zone to the net, used to turn flight
  /// time into a speed.
  final double shotDistanceFeet;

  /// Outputs: [puckDiameter] if measured, otherwise a guess assuming the
  /// shooting zone was drawn about 4 ft wide (a 3 in puck is 1/16 of that).
  double get effectivePuckDiameter => puckDiameter ?? math.max(shootingZone.width / 16, 0.01);

  Map<String, dynamic> toJson() => {
        'zone': shootingZone.toJson(),
        'net': net.toJson(),
        if (puckDiameter != null) 'puck': puckDiameter,
        'feet': shotDistanceFeet,
      };

  String encode() => jsonEncode(toJson());
}
