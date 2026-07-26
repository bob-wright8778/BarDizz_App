import 'package:shared_preferences/shared_preferences.dart';

const String _key = 'eww_always_bar_down';

/// Single source of truth for the toggle's default (card 15) -- referenced by
/// every layer that needs a value before the store has loaded
/// (`ClassifierDetector`, `_AppHomeGateState`, `_SettingsScreenState`).
const bool ewwAlwaysBarDownDefault = true;

/// Outputs: [ewwAlwaysBarDownDefault], as a tear-off-able function (a shared
/// constructor default).
bool ewwAlwaysBarDownDefaultGetter() => ewwAlwaysBarDownDefault;

/// Persists whether a standalone `eww` classification counts as a bar-down on
/// its own, bypassing the confirming bar-hit stage -- a temporary workaround
/// for nets whose bar-hit impact isn't reliably classified but whose "Eww"
/// reaction still is (Kanban card 15). Defaults on.
class EwwAlwaysBarDownStore {
  const EwwAlwaysBarDownStore();

  /// Outputs: the persisted toggle value, or [ewwAlwaysBarDownDefault] if
  /// nothing has been saved yet.
  Future<bool> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? ewwAlwaysBarDownDefault;
  }

  /// Inputs: the new toggle value to persist.
  Future<void> save(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, value);
  }
}
