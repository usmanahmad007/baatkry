import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../theme/app_theme.dart';

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(AppTheme.themeModeNotifier.value) {
    AppTheme.themeModeNotifier.addListener(_sync);
  }

  void _sync() {
    if (state != AppTheme.themeModeNotifier.value) {
      state = AppTheme.themeModeNotifier.value;
    }
  }

  void toggleTheme() {
    AppTheme.cycleThemeMode();
    state = AppTheme.themeModeNotifier.value;
  }

  void setTheme(ThemeMode mode) {
    AppTheme.setThemeMode(mode);
    state = mode;
  }

  @override
  void dispose() {
    AppTheme.themeModeNotifier.removeListener(_sync);
    super.dispose();
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier();
});
