import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hockey_shot_tracker/theme/design_tokens.dart';

void main() {
  group('AppColors', () {
    test('neutral ink scale matches the design handoff', () {
      expect(AppColors.ink900, const Color(0xFF101214));
      expect(AppColors.ink800, const Color(0xFF181B1E));
      expect(AppColors.ink700, const Color(0xFF202427));
      expect(AppColors.ink600, const Color(0xFF2B3033));
      expect(AppColors.ink500, const Color(0xFF3C4247));
      expect(AppColors.ink400, const Color(0xFF585F64));
      expect(AppColors.ink300, const Color(0xFF7E868C));
      expect(AppColors.ink200, const Color(0xFFA9B0B5));
      expect(AppColors.ink100, const Color(0xFFD8DCDE));
      expect(AppColors.ink50, const Color(0xFFF2F4F5));
    });

    test('ice blue (primary) scale matches the design handoff', () {
      expect(AppColors.iceBlueTint, const Color(0xFFEAF4F8));
      expect(AppColors.iceBlueLight, const Color(0xFFB9DCE7));
      expect(AppColors.iceBluePrimary, const Color(0xFF6FA9C2));
      expect(AppColors.iceBluePressed, const Color(0xFF3E7590));
    });

    test('graphite (secondary) scale matches the design handoff', () {
      expect(AppColors.graphiteTint, const Color(0xFFEAECED));
      expect(AppColors.graphiteLight, const Color(0xFF9AA1A6));
      expect(AppColors.graphiteSecondary, const Color(0xFF5B6670));
      expect(AppColors.graphitePressed, const Color(0xFF33383D));
    });

    test('semantic colors match the design handoff', () {
      expect(AppColors.success, const Color(0xFF4CAF6D));
      expect(AppColors.warning, const Color(0xFFE8A23D));
      expect(AppColors.error, const Color(0xFFC23B3B));
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
