import 'package:shared_preferences/shared_preferences.dart';

import '../video/video_calibration.dart';

const String _calibrationKey = 'video_calibration';
const String _requireSoundKey = 'video_require_sound';

/// Default for whether a camera-detected shot also needs a stick-on-puck
/// sound to count.
const bool requireSoundDefault = true;

/// Persists the camera calibration and the "require sound" toggle.
class VideoSettingsStore {
  const VideoSettingsStore();

  /// Outputs: the saved calibration, or `null` if the camera was never
  /// calibrated (or the saved value is unreadable).
  Future<VideoCalibration?> loadCalibration() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_calibrationKey);
    if (raw == null) return null;
    try {
      return VideoCalibration.decode(raw);
    } on Object {
      return null;
    }
  }

  Future<void> saveCalibration(VideoCalibration calibration) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_calibrationKey, calibration.encode());
  }

  Future<bool> loadRequireSound() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_requireSoundKey) ?? requireSoundDefault;
  }

  Future<void> saveRequireSound(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_requireSoundKey, value);
  }
}
