import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/settings/eww_always_bar_down_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('EwwAlwaysBarDownStore', () {
    test('load defaults to true before anything is saved', () async {
      const store = EwwAlwaysBarDownStore();
      expect(await store.load(), isTrue);
    });

    test('save then load round-trips false', () async {
      const store = EwwAlwaysBarDownStore();
      await store.save(false);
      expect(await store.load(), isFalse);
    });

    test('save then load round-trips true after having been set false', () async {
      const store = EwwAlwaysBarDownStore();
      await store.save(false);
      await store.save(true);
      expect(await store.load(), isTrue);
    });
  });
}
