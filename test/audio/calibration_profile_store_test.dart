import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/audio/calibration_profile_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('CalibrationProfileStore', () {
    test('hasProfile is false before anything is saved', () async {
      const store = CalibrationProfileStore();
      expect(await store.hasProfile(), isFalse);
    });

    test('loadProfile returns null before anything is saved', () async {
      const store = CalibrationProfileStore();
      expect(await store.loadProfile(), isNull);
    });

    test('saveProfile then loadProfile round-trips the same values', () async {
      const store = CalibrationProfileStore();
      const profile = [0.05, 0.10, 0.20, 0.25, 0.25, 0.15];

      await store.saveProfile(profile);
      final loaded = await store.loadProfile();

      expect(loaded, isNotNull);
      for (var i = 0; i < profile.length; i++) {
        expect(loaded![i], closeTo(profile[i], 1e-9));
      }
    });

    test('hasProfile is true after saving', () async {
      const store = CalibrationProfileStore();
      await store.saveProfile([0.5, 0.5]);
      expect(await store.hasProfile(), isTrue);
    });

    test('a custom key persists independently of the default key', () async {
      const shotStore = CalibrationProfileStore();
      const ewwStore = CalibrationProfileStore(key: ewwProfileKey);

      await shotStore.saveProfile([0.1, 0.2]);

      expect(await ewwStore.hasProfile(), isFalse);
      expect(await ewwStore.loadProfile(), isNull);

      await ewwStore.saveProfile([0.9, 0.8]);
      final shotLoaded = await shotStore.loadProfile();
      final ewwLoaded = await ewwStore.loadProfile();

      expect(shotLoaded, [0.1, 0.2]);
      expect(ewwLoaded, [0.9, 0.8]);
    });
  });
}
