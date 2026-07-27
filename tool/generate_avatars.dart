// Deterministic generator for the 24-avatar bundled set: 4 hockey motifs
// (puck/stick/helmet/jersey) x 6 accent colors drawn from
// lib/theme/design_tokens.dart, re-run any time to regenerate identical
// output. Usage: dart run tool/generate_avatars.dart
import 'dart:io';

/// One design-token accent color reused as an avatar's motif fill.
class _Accent {
  const _Accent(this.name, this.hex);

  final String name;
  final String hex;
}

// Matches lib/theme/design_tokens.dart's AppColors. AppColors.error is
// excluded -- the design handoff reserves it as the logo's own accent, not a
// general-purpose UI color.
const _accents = [
  _Accent('ice-blue-primary', '#6FA9C2'),
  _Accent('ice-blue-light', '#B9DCE7'),
  _Accent('graphite-secondary', '#5B6670'),
  _Accent('graphite-light', '#9AA1A6'),
  _Accent('success', '#4CAF6D'),
  _Accent('warning', '#E8A23D'),
];

const _background = '#181B1E'; // AppColors.ink800 (cardSurface)
const _outline = '#2B3033'; // AppColors.ink600

typedef _MotifBuilder = String Function(String accent);

const _motifs = <String, _MotifBuilder>{
  'puck': _puck,
  'stick': _stick,
  'helmet': _helmet,
  'jersey': _jersey,
};

/// Outputs: an SVG `<g>` body drawing a hockey puck viewed edge-on.
String _puck(String accent) => '''
  <ellipse cx="32" cy="36" rx="20" ry="9" fill="$_outline" />
  <ellipse cx="32" cy="32" rx="20" ry="9" fill="$accent" />
  <ellipse cx="32" cy="32" rx="12" ry="4" fill="$_background" opacity="0.35" />
''';

/// Outputs: an SVG `<g>` body drawing a crossed hockey stick and puck.
String _stick(String accent) => '''
  <rect x="14" y="44" width="34" height="6" rx="3" fill="$accent"
      transform="rotate(-35 14 44)" />
  <rect x="10" y="40" width="10" height="14" rx="2" fill="$accent"
      transform="rotate(-35 10 40)" />
  <circle cx="44" cy="46" r="7" fill="$_outline" />
''';

/// Outputs: an SVG `<g>` body drawing a rounded goalie-mask silhouette.
String _helmet(String accent) => '''
  <path d="M32 12c-12 0-20 9-20 21 0 9 5 15 10 18h20c5-3 10-9 10-18 0-12-8-21-20-21z"
      fill="$accent" />
  <rect x="20" y="34" width="24" height="5" fill="$_background" opacity="0.5" />
  <rect x="20" y="42" width="24" height="5" fill="$_background" opacity="0.5" />
''';

/// Outputs: an SVG `<g>` body drawing a jersey with a V-neck collar.
String _jersey(String accent) => '''
  <path d="M18 20l10-6 4 5 4-5 10 6 6 8-6 4v22H18V32l-6-4z" fill="$accent" />
  <path d="M28 14l4 5 4-5" stroke="$_background" stroke-width="2" fill="none" />
''';

/// Outputs: a full standalone SVG document string for one avatar.
String _svgFor(String motifName, _MotifBuilder motif, _Accent accent) {
  final body = motif(accent.hex);
  return '''
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64">
  <!-- $motifName / ${accent.name} -->
  <circle cx="32" cy="32" r="31" fill="$_background" stroke="$_outline" stroke-width="2" />
$body</svg>
''';
}

void main() {
  final outDir = Directory('assets/avatars');
  outDir.createSync(recursive: true);

  var index = 1;
  for (final motifEntry in _motifs.entries) {
    for (final accent in _accents) {
      final id = 'avatar-${index.toString().padLeft(2, '0')}';
      final svg = _svgFor(motifEntry.key, motifEntry.value, accent);
      File('${outDir.path}/$id.svg').writeAsStringSync(svg);
      index++;
    }
  }

  stdout.writeln('Generated ${index - 1} avatars in ${outDir.path}');
}
