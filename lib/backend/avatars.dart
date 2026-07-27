/// The 24 bundled avatar IDs (stable filename stems), in generator order.
final List<String> avatarIds = [
  for (var i = 1; i <= 24; i++) 'avatar-${i.toString().padLeft(2, '0')}',
];

/// Inputs: an avatar id (e.g. "avatar-07").
/// Outputs: its bundled asset path.
String avatarAssetPath(String avatarId) => 'assets/avatars/$avatarId.svg';
