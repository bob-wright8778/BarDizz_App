import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../video/distance_estimate.dart';
import '../video/luma_frame.dart';
import '../video/norm_rect.dart';
import '../video/puck_finder.dart';
import '../video/video_calibration.dart';
import '../video/video_shot_controller.dart';
import '../widgets/app_card.dart';

enum _Marking { zone, net }

/// Lets the user mark the shooting zone and the net on a still from the
/// camera, measures the resting puck, and works out the shooting distance
/// from the size of a regulation net and puck (or takes it by hand).
///
/// The still is shown upright for however the phone is standing; the
/// rotation is guessed from the phone's orientation, and "Rotate" fixes a
/// wrong guess. The tracker applies the same rotation to every frame, so the
/// marked boxes line up with detection.
class VideoCalibrationScreen extends StatefulWidget {
  const VideoCalibrationScreen({super.key, required this.feed});

  final VideoShotFeed feed;

  @override
  State<VideoCalibrationScreen> createState() => _VideoCalibrationScreenState();
}

class _VideoCalibrationScreenState extends State<VideoCalibrationScreen> {
  LumaFrame? _raw;
  LumaFrame? _frame;
  ui.Image? _image;
  bool _loading = true;
  late int _quarterTurns;
  _Marking _marking = _Marking.zone;
  NormRect? _zone;
  NormRect? _net;
  PuckMeasurement? _puck;
  bool _manualDistance = false;
  double _manualFeet = VideoCalibration.defaultShotDistanceFeet;
  Offset? _dragStart;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.feed.calibration;
    _quarterTurns = existing?.quarterTurns ?? widget.feed.suggestedQuarterTurns;
    if (existing != null) {
      _zone = existing.shootingZone;
      _net = existing.net;
      _manualDistance = existing.distanceIsManual;
      _manualFeet = existing.shotDistanceFeet.clamp(_minFeet, _maxFeet);
    }
    _takeSnapshot();
  }

  static const double _minFeet = 6;
  static const double _maxFeet = 40;

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  double? get _estimatedFeet {
    final frame = _frame;
    final net = _net;
    final puck = _puck;
    if (frame == null || net == null || puck == null) return null;
    return estimateShotDistanceFeet(net: net, puck: puck, aspect: frame.width / frame.height);
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    await _takeSnapshot();
  }

  Future<void> _takeSnapshot() async {
    final raw = await widget.feed.captureStill();
    if (!mounted) return;
    _raw = raw;
    await _showUpright();
  }

  Future<void> _showUpright() async {
    final raw = _raw;
    if (raw == null) {
      setState(() => _loading = false);
      return;
    }
    final frame = rotateLuma(raw, _quarterTurns);
    final image = await _toImage(frame);
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
      _frame = frame;
      _loading = false;
      _measurePuck();
    });
  }

  static Future<ui.Image> _toImage(LumaFrame frame) {
    final rgba = Uint8List(frame.width * frame.height * 4);
    for (var i = 0; i < frame.pixels.length; i++) {
      final v = frame.pixels[i];
      rgba[i * 4] = v;
      rgba[i * 4 + 1] = v;
      rgba[i * 4 + 2] = v;
      rgba[i * 4 + 3] = 255;
    }
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(rgba, frame.width, frame.height, ui.PixelFormat.rgba8888, completer.complete);
    return completer.future;
  }

  /// Turns the still a quarter turn clockwise. Marked boxes are cleared:
  /// they were drawn on the old orientation.
  Future<void> _rotate() async {
    setState(() {
      _quarterTurns = (_quarterTurns + 1) % 4;
      _zone = null;
      _net = null;
      _puck = null;
    });
    await _showUpright();
  }

  void _measurePuck() {
    final frame = _frame;
    final zone = _zone;
    if (frame == null || zone == null) return;
    _puck = measurePuck(frame, zone, guessWidth: zone.width / 16);
  }

  void _onPanStart(DragStartDetails d, Size size) {
    _dragStart = Offset(d.localPosition.dx / size.width, d.localPosition.dy / size.height);
  }

  void _onPanUpdate(DragUpdateDetails d, Size size) {
    final start = _dragStart;
    if (start == null) return;
    final rect = NormRect.fromCorners(
      start.dx,
      start.dy,
      d.localPosition.dx / size.width,
      d.localPosition.dy / size.height,
    );
    setState(() {
      if (_marking == _Marking.zone) {
        _zone = rect;
      } else {
        _net = rect;
      }
    });
  }

  void _onPanEnd() {
    _dragStart = null;
    if (_marking == _Marking.zone) setState(_measurePuck);
  }

  Future<void> _save() async {
    final zone = _zone;
    final net = _net;
    if (zone == null || net == null) return;
    final estimate = _estimatedFeet;
    final manual = _manualDistance || estimate == null;
    setState(() => _saving = true);
    await widget.feed.setCalibration(VideoCalibration(
      shootingZone: zone,
      net: net,
      quarterTurns: _quarterTurns,
      puckWidth: _puck?.width,
      puckHeight: _puck?.height,
      shotDistanceFeet: manual ? _manualFeet : estimate,
      distanceIsManual: manual,
    ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    final image = _image;
    final estimate = _estimatedFeet;

    return Scaffold(
      appBar: AppBar(title: const Text('Camera setup')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const Text(
              'Stand the phone up, upright or sideways, behind or beside you, with '
              'the net and the spot you shoot from both in view. Put a puck where '
              'you shoot from, then drag a box around the shooting spot and one '
              "around the net's opening (posts and crossbar).",
              style: AppTypography.body,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (frame == null || image == null)
              const AppCard(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'The camera is not running. Start a session, then open this again.',
                  key: Key('calibrationNoCameraText'),
                  style: AppTypography.body,
                ),
              )
            else ...[
              AspectRatio(
                aspectRatio: frame.width / frame.height,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = constraints.biggest;
                    return GestureDetector(
                      key: const Key('calibrationCanvas'),
                      // Box corners start where the finger lands, not where
                      // the drag is first recognised a few pixels later.
                      dragStartBehavior: DragStartBehavior.down,
                      onPanStart: (d) => _onPanStart(d, size),
                      onPanUpdate: (d) => _onPanUpdate(d, size),
                      onPanEnd: (_) => _onPanEnd(),
                      child: CustomPaint(
                        foregroundPainter: _MarkingsPainter(zone: _zone, net: _net),
                        child: RawImage(image: image, fit: BoxFit.fill, filterQuality: FilterQuality.none),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  TextButton.icon(
                    key: const Key('calibrationRotateButton'),
                    onPressed: _rotate,
                    icon: const Icon(Icons.rotate_right),
                    label: const Text('Rotate'),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    key: const Key('calibrationRefreshButton'),
                    onPressed: _refresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
              const Text('If the picture is sideways, tap Rotate.', style: AppTypography.caption),
              const SizedBox(height: AppSpacing.md),
              SegmentedButton<_Marking>(
                segments: const [
                  ButtonSegment(value: _Marking.zone, label: Text('Shooting spot')),
                  ButtonSegment(value: _Marking.net, label: Text('Net')),
                ],
                selected: {_marking},
                onSelectionChanged: (s) => setState(() => _marking = s.single),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                _zone == null
                    ? 'Mark the shooting spot first.'
                    : _puck == null
                        ? 'No puck found in the shooting spot. Place one and tap Refresh.'
                        : 'Puck found.',
                key: const Key('calibrationPuckStatus'),
                style: AppTypography.body,
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Distance to net', style: AppTypography.label),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    estimate != null
                        ? 'About ${estimate.round()} ft, worked out from the size of a regulation '
                            '6 x 4 ft net and puck.'
                        : 'Mark the net and the puck and it will be worked out from their size.',
                    key: const Key('calibrationEstimateText'),
                    style: AppTypography.body,
                  ),
                  SwitchListTile(
                    key: const Key('calibrationManualDistanceSwitch'),
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Set distance myself'),
                    subtitle: const Text('For a smaller net, or if you measured it.'),
                    value: _manualDistance,
                    onChanged: (v) => setState(() {
                      _manualDistance = v;
                      if (v && estimate != null) _manualFeet = estimate.clamp(_minFeet, _maxFeet);
                    }),
                  ),
                  if (_manualDistance) ...[
                    Text('${_manualFeet.round()} ft', style: AppTypography.label),
                    Slider(
                      key: const Key('calibrationDistanceSlider'),
                      value: _manualFeet,
                      min: _minFeet,
                      max: _maxFeet,
                      divisions: (_maxFeet - _minFeet).round(),
                      onChanged: (v) => setState(() => _manualFeet = v),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              key: const Key('calibrationSaveButton'),
              onPressed: (_zone == null || _net == null || _saving) ? null : _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarkingsPainter extends CustomPainter {
  _MarkingsPainter({required this.zone, required this.net});

  final NormRect? zone;
  final NormRect? net;

  @override
  void paint(Canvas canvas, Size size) {
    void box(NormRect? r, Color color) {
      if (r == null) return;
      canvas.drawRect(
        Rect.fromLTRB(r.left * size.width, r.top * size.height, r.right * size.width, r.bottom * size.height),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color,
      );
    }

    box(zone, AppColors.iceBluePrimary);
    box(net, AppColors.warning);
  }

  @override
  bool shouldRepaint(_MarkingsPainter old) => old.zone != zone || old.net != net;
}
