import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../theme/design_tokens.dart';
import '../video/luma_frame.dart';
import '../video/norm_rect.dart';
import '../video/puck_finder.dart';
import '../video/video_calibration.dart';
import '../video/video_shot_controller.dart';
import '../widgets/app_card.dart';

enum _Marking { zone, net }

/// Lets the user mark the shooting zone and the net on a still from the
/// camera, measures the resting puck, and sets the shooting distance.
///
/// The still is the same analysis grid the tracker sees, shown in the
/// camera sensor's own orientation, so the marked rectangles line up with
/// detection exactly regardless of how the phone is rotated.
class VideoCalibrationScreen extends StatefulWidget {
  const VideoCalibrationScreen({super.key, required this.feed});

  final VideoShotFeed feed;

  @override
  State<VideoCalibrationScreen> createState() => _VideoCalibrationScreenState();
}

class _VideoCalibrationScreenState extends State<VideoCalibrationScreen> {
  LumaFrame? _frame;
  ui.Image? _image;
  _Marking _marking = _Marking.zone;
  NormRect? _zone;
  NormRect? _net;
  double? _puckDiameter;
  double _distanceFeet = VideoCalibration.defaultShotDistanceFeet;
  Offset? _dragStart;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final existing = widget.feed.calibration;
    if (existing != null) {
      _zone = existing.shootingZone;
      _net = existing.net;
      _puckDiameter = existing.puckDiameter;
      _distanceFeet = existing.shotDistanceFeet;
    }
    _takeSnapshot();
  }

  @override
  void dispose() {
    _image?.dispose();
    super.dispose();
  }

  Future<void> _takeSnapshot() async {
    final frame = widget.feed.latestFrame.value;
    if (frame == null) return;
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
    final image = await completer.future;
    if (!mounted) {
      image.dispose();
      return;
    }
    setState(() {
      _image?.dispose();
      _image = image;
      _frame = frame;
      _measurePuck();
    });
  }

  void _measurePuck() {
    final frame = _frame;
    final zone = _zone;
    if (frame == null || zone == null) return;
    _puckDiameter = measurePuckDiameter(frame, zone, guessDiameter: zone.width / 16);
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
    setState(() => _saving = true);
    await widget.feed.setCalibration(VideoCalibration(
      shootingZone: zone,
      net: net,
      puckDiameter: _puckDiameter,
      shotDistanceFeet: _distanceFeet,
    ));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final frame = _frame;
    final image = _image;

    return Scaffold(
      appBar: AppBar(title: const Text('Camera setup')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            const Text(
              'Mount the phone sideways behind or beside you, with the net and the '
              'spot you shoot from both in view. Put a puck where you shoot from, '
              'then drag a box around each.',
              style: AppTypography.body,
            ),
            const SizedBox(height: AppSpacing.lg),
            if (frame == null || image == null)
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _zone == null
                          ? 'Mark the shooting spot first.'
                          : _puckDiameter == null
                              ? 'No puck found in the shooting spot. Place one and refresh.'
                              : 'Puck found.',
                      key: const Key('calibrationPuckStatus'),
                      style: AppTypography.body,
                    ),
                  ),
                  TextButton.icon(
                    key: const Key('calibrationRefreshButton'),
                    onPressed: _takeSnapshot,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Refresh'),
                  ),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            Text('Distance to net: ${_distanceFeet.round()} ft', style: AppTypography.label),
            Slider(
              key: const Key('calibrationDistanceSlider'),
              value: _distanceFeet,
              min: 6,
              max: 40,
              divisions: 34,
              onChanged: (v) => setState(() => _distanceFeet = v),
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
