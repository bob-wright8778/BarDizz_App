import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/theme/design_tokens.dart';

void main() {
  group('AppColors', () {
    test('neutral ink scale matches the design handoff', () {
      expect(AppColors.ink900, const Color(0xFF0E0E10));
      expect(AppColors.ink800, const Color(0xFF17171A));
      expect(AppColors.ink700, const Color(0xFF1F1F23));
      expect(AppColors.ink600, const Color(0xFF2A2A2E));
      expect(AppColors.ink500, const Color(0xFF3A3A40));
      expect(AppColors.ink400, const Color(0xFF55555C));
      expect(AppColors.ink300, const Color(0xFF7A7A82));
      expect(AppColors.ink200, const Color(0xFFA8A8AE));
      expect(AppColors.ink100, const Color(0xFFD6D6DA));
      expect(AppColors.ink50, const Color(0xFFF5F5F7));
    });

    test('magenta (primary) scale matches the design handoff', () {
      expect(AppColors.magentaTint, const Color(0xFFF7E4F0));
      expect(AppColors.magentaLight, const Color(0xFFE39CC8));
      expect(AppColors.magentaPrimary, const Color(0xFFC24FA0));
      expect(AppColors.magentaPressed, const Color(0xFF8A3671));
    });

    test('teal (secondary) scale matches the design handoff', () {
      expect(AppColors.tealTint, const Color(0xFFE3FBF8));
      expect(AppColors.tealLight, const Color(0xFF9DE8E0));
      expect(AppColors.tealSecondary, const Color(0xFF3FC9BE));
      expect(AppColors.tealPressed, const Color(0xFF237871));
    });

    test('semantic colors match the design handoff', () {
      expect(AppColors.success, const Color(0xFF4CAF6D));
      expect(AppColors.warning, const Color(0xFFE8A23D));
      expect(AppColors.error, const Color(0xFFE0524A));
    });

    test('page background and card surface are the darkest two neutrals', () {
      expect(AppColors.pageBackground, AppColors.ink900);
      expect(AppColors.cardSurface, AppColors.ink800);
    });
  });

  group('AppSpacing', () {
    test('4px base-unit scale matches the design handoff', () {
      expect(AppSpacing.xs, 4.0);
      expect(AppSpacing.sm, 8.0);
      expect(AppSpacing.md, 12.0);
      expect(AppSpacing.lg, 16.0);
      expect(AppSpacing.xl, 24.0);
      expect(AppSpacing.xxl, 32.0);
      expect(AppSpacing.xxxl, 48.0);
      expect(AppSpacing.huge, 64.0);
    });
  });

  group('AppRadius', () {
    test('radius scale matches the design handoff', () {
      expect(AppRadius.sm, 4.0);
      expect(AppRadius.md, 8.0);
      expect(AppRadius.lg, 16.0);
      expect(AppRadius.xl, 24.0);
      expect(AppRadius.pill, 999.0);
    });
  });

  group('AppElevation', () {
    test('three levels are defined with increasing blur/offset', () {
      expect(AppElevation.level1, hasLength(1));
      expect(AppElevation.level2, hasLength(1));
      expect(AppElevation.level3, hasLength(1));
      expect(AppElevation.level1.single.blurRadius, lessThan(AppElevation.level2.single.blurRadius));
      expect(AppElevation.level2.single.blurRadius, lessThan(AppElevation.level3.single.blurRadius));
    });
  });

  group('AppTypography', () {
    test('display style matches the design handoff (56/700)', () {
      expect(AppTypography.display.fontSize, 56);
      expect(AppTypography.display.fontWeight, FontWeight.w700);
      expect(AppTypography.display.fontFamily, 'Barlow Condensed');
    });

    test('h1 style matches the design handoff (36/700)', () {
      expect(AppTypography.h1.fontSize, 36);
      expect(AppTypography.h1.fontWeight, FontWeight.w700);
      expect(AppTypography.h1.fontFamily, 'Barlow Condensed');
    });

    test('h2 style matches the design handoff (26/600)', () {
      expect(AppTypography.h2.fontSize, 26);
      expect(AppTypography.h2.fontWeight, FontWeight.w600);
      expect(AppTypography.h2.fontFamily, 'Barlow Condensed');
    });

    test('bodyL style matches the design handoff (18/500, Manrope)', () {
      expect(AppTypography.bodyL.fontSize, 18);
      expect(AppTypography.bodyL.fontWeight, FontWeight.w500);
      expect(AppTypography.bodyL.fontFamily, 'Manrope');
    });

    test('body style matches the design handoff (16/400, Manrope)', () {
      expect(AppTypography.body.fontSize, 16);
      expect(AppTypography.body.fontWeight, FontWeight.w400);
      expect(AppTypography.body.fontFamily, 'Manrope');
    });

    test('label style matches the design handoff (14/600, Manrope)', () {
      expect(AppTypography.label.fontSize, 14);
      expect(AppTypography.label.fontWeight, FontWeight.w600);
      expect(AppTypography.label.fontFamily, 'Manrope');
    });

    test('overline style matches the design handoff (11/700, 1.5px tracking, Manrope)', () {
      expect(AppTypography.overline.fontSize, 11);
      expect(AppTypography.overline.fontWeight, FontWeight.w700);
      expect(AppTypography.overline.letterSpacing, 1.5);
      expect(AppTypography.overline.fontFamily, 'Manrope');
    });
  });
}
