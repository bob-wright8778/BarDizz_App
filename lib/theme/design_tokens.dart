import 'package:flutter/material.dart';

/// Color tokens from the "SHOTLOG DESIGN SYSTEM" handoff (design/ft9pro.pdf)
/// — final values, not placeholders.
class AppColors {
  const AppColors._();

  // Neutrals / ink scale, dark -> light.
  static const ink900 = Color(0xFF101214);
  static const ink800 = Color(0xFF181B1E);
  static const ink700 = Color(0xFF202427);
  static const ink600 = Color(0xFF2B3033);
  static const ink500 = Color(0xFF3C4247);
  static const ink400 = Color(0xFF585F64);
  static const ink300 = Color(0xFF7E868C);
  static const ink200 = Color(0xFFA9B0B5);
  static const ink100 = Color(0xFFD8DCDE);
  static const ink50 = Color(0xFFF2F4F5);

  // Ice Blue -- primary accent.
  static const iceBlueTint = Color(0xFFEAF4F8);
  static const iceBlueLight = Color(0xFFB9DCE7);
  static const iceBluePrimary = Color(0xFF6FA9C2);
  static const iceBluePressed = Color(0xFF3E7590);

  // Graphite -- secondary accent.
  static const graphiteTint = Color(0xFFEAECED);
  static const graphiteLight = Color(0xFF9AA1A6);
  static const graphiteSecondary = Color(0xFF5B6670);
  static const graphitePressed = Color(0xFF33383D);

  // Semantic. Error doubles as the logo's jet-red accent (net photo pipe
  // color) -- not used elsewhere as a general UI accent, see design handoff.
  static const success = Color(0xFF4CAF6D);
  static const warning = Color(0xFFE8A23D);
  static const error = Color(0xFFC23B3B);

  static const pageBackground = ink900;
  static const cardSurface = ink800;
}

/// Spacing scale (4px base unit) from the design handoff.
class AppSpacing {
  const AppSpacing._();

  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 48.0;
  static const huge = 64.0;
}

/// Corner-radius scale from the design handoff.
class AppRadius {
  const AppRadius._();

  static const sm = 4.0;
  static const md = 8.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const pill = 999.0;
}

/// Elevation shadows from the design handoff, translated from CSS box-shadow
/// to Flutter's BoxShadow (blur/offset are a close visual match, not a
/// pixel-identical port — per the handoff's own "recreate, don't copy" note).
class AppElevation {
  const AppElevation._();

  static const level1 = [
    BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.45), blurRadius: 2, offset: Offset(0, 1)),
  ];
  static const level2 = [
    BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.5), blurRadius: 14, offset: Offset(0, 4)),
  ];
  static const level3 = [
    BoxShadow(color: Color.fromRGBO(0, 0, 0, 0.55), blurRadius: 36, offset: Offset(0, 16)),
  ];
}

/// Type scale from the design handoff. H1 and Overline are defined
/// uppercase in the source; callers apply `.toUpperCase()` to the text
/// themselves since TextStyle has no text-transform equivalent.
class AppTypography {
  const AppTypography._();

  static const _display = 'Barlow Condensed';
  static const _body = 'Manrope';

  static const display = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.w700,
    fontSize: 56,
    letterSpacing: 0.5,
    color: AppColors.ink50,
  );

  static const h1 = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.w700,
    fontSize: 36,
    letterSpacing: 0.5,
    color: AppColors.ink50,
  );

  static const h2 = TextStyle(
    fontFamily: _display,
    fontWeight: FontWeight.w600,
    fontSize: 26,
    letterSpacing: 0.3,
    color: AppColors.ink50,
  );

  static const bodyL = TextStyle(
    fontFamily: _body,
    fontWeight: FontWeight.w500,
    fontSize: 18,
    color: AppColors.ink50,
  );

  static const body = TextStyle(
    fontFamily: _body,
    fontWeight: FontWeight.w400,
    fontSize: 16,
    color: AppColors.ink50,
  );

  static const label = TextStyle(
    fontFamily: _body,
    fontWeight: FontWeight.w600,
    fontSize: 14,
    letterSpacing: 0.2,
    color: AppColors.ink50,
  );

  static const overline = TextStyle(
    fontFamily: _body,
    fontWeight: FontWeight.w700,
    fontSize: 11,
    letterSpacing: 1.5,
    color: AppColors.ink50,
  );

  /// Muted/secondary body text (goal labels, session metadata, mic-level
  /// readouts) -- same scale as [body], ink300 instead of ink50.
  static const caption = TextStyle(
    fontFamily: _body,
    fontWeight: FontWeight.w400,
    fontSize: 16,
    color: AppColors.ink300,
  );

  /// Inline error text -- same scale as [body], error color instead of ink50.
  static const errorText = TextStyle(
    fontFamily: _body,
    fontWeight: FontWeight.w400,
    fontSize: 16,
    color: AppColors.error,
  );
}
