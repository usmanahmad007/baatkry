import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:monkey_omegle_app/core/theme/app_theme.dart';

void main() {
  group('Black & White Theme Mode Tests', () {
    test('Default theme mode is ThemeMode.system', () {
      expect(AppTheme.themeModeNotifier.value, ThemeMode.system);
    });

    test('Theme colors have high-contrast Black and White values', () {
      expect(AppColors.darkBackground, const Color(0xFF090A10));
      expect(AppColors.lightBackground, const Color(0xFFF8FAFC));
      expect(AppColors.darkSurface, const Color(0xFF14172B));
      expect(AppColors.lightSurface, const Color(0xFFFFFFFF));
      expect(AppColors.darkTextPrimary, const Color(0xFFFFFFFF));
      expect(AppColors.lightTextPrimary, const Color(0xFF0F172A));
    });

    test('Cycling theme mode iterates System -> Black -> White -> System', () {
      AppTheme.setThemeMode(ThemeMode.system);
      expect(AppTheme.themeModeNotifier.value, ThemeMode.system);

      AppTheme.cycleThemeMode();
      expect(AppTheme.themeModeNotifier.value, ThemeMode.dark);

      AppTheme.cycleThemeMode();
      expect(AppTheme.themeModeNotifier.value, ThemeMode.light);

      AppTheme.cycleThemeMode();
      expect(AppTheme.themeModeNotifier.value, ThemeMode.system);
    });

    testWidgets('ThemeData builds without errors in widget test', (tester) async {
      final dark = AppTheme.darkTheme;
      final light = AppTheme.lightTheme;
      expect(dark.brightness, Brightness.dark);
      expect(light.brightness, Brightness.light);
    });
  });
}
