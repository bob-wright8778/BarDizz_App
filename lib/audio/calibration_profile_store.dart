import 'package:shared_preferences/shared_preferences.dart';

const String _profileKey = 'calibration_reference_profile';

/// Persists the user's calibrated shot spectral profile locally via
/// [SharedPreferences], so detection can use it across app restarts instead
/// of the built-in placeholder.
class CalibrationProfileStore {
  const CalibrationProfileStore();

  /// Outputs: the stored reference profile, or `null` if calibration hasn't
  /// been done yet.
  Future<List<double>?> loadProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_profileKey);
    if (stored == null) return null;
    return stored.map(double.parse).toList();
  }

  /// Inputs: [profile] the derived per-band reference profile to persist.
  Future<void> saveProfile(List<double> profile) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_profileKey, profile.map((v) => v.toString()).toList());
  }

  /// Outputs: whether a calibration profile has been saved.
  Future<bool> hasProfile() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_profileKey);
  }
}
