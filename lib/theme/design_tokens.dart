import 'package:flutter/material.dart';

/// Color tokens from the "Hockey Shot Tracker Design System" handoff
/// (design/Hockey Shot Practice System.zip) — final values, not placeholders.
class AppColors {
  const AppColors._();

  // Neutrals / ink scale, dark -> light.
  static const ink900 = Color(0xFF0E0E10);
  static const ink800 = Color(0xFF17171A);
  static const ink700 = Color(0xFF1F1F23);
  static const ink600 = Color(0xFF2A2A2E);
  static const ink500 = Color(0xFF3A3A40);
  static const ink400 = Color(0xFF55555C);
  static const ink300 = Color(0xFF7A7A82);
  static const ink200 = Color(0xFFA8A8AE);
  static const ink100 = Color(0xFFD6D6DA);
  static const ink50 = Color(0xFFF5F5F7);

  // Magenta -- primary accent.
  static const magentaTint = Color(0xFFF7E4F0);
  static const magentaLight = Color(0xFFE39CC8);
  static const magentaPrimary = Color(0xFFC24FA0);
  static const magentaPressed = Color(0xFF8A3671);

  // Teal -- secondary accent.
  static const tealTint = Color(0xFFE3FBF8);
  static const tealLight = Color(0xFF9DE8E0);
  static const tealSecondary = Color(0xFF3FC9BE);
  static const tealPressed = Color(0xFF237871);

  // Ice blue -- BAR DIZZ banner / Bar Down dial accent.
  static const iceBlueTint = Color(0xFFE1F2FC);
  static const iceBlueLight = Color(0xFF86CFF2);
  static const iceBluePrimary = Color(0xFF2AA8E0);
  static const iceBluePressed = Color(0xFF176F98);

  // Semantic.
  static const success = Color(0xFF4CAF6D);
  static const warning = Color(0xFFE8A23D);
  static const error = Color(0xFFE0524A);

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
