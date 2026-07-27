import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/backend/avatars.dart';

void main() {
  test('exposes exactly 24 distinct avatar ids', () {
    expect(avatarIds.length, 24);
    expect(avatarIds.toSet().length, 24);
  });

  test('avatar ids follow the avatar-NN stem convention', () {
    for (final id in avatarIds) {
      expect(id, matches(RegExp(r'^avatar-\d{2}$')));
    }
  });

  test('avatarAssetPath points at the bundled assets/avatars folder', () {
    expect(avatarAssetPath('avatar-07'), 'assets/avatars/avatar-07.svg');
  });
}
