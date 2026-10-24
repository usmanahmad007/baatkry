import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  AppColors._();

  // Dark obsidian (Black theme)
  static const Color darkBackground = Color(0xFF090A10);
  static const Color darkBackgroundElevated = Color(0xFF101322);
  static const Color darkSurface = Color(0xFF14172B);
  static const Color darkSurfaceElevated = Color(0xFF1D223B);
  static const Color darkSurfaceBorder = Color(0xFF2A3152);
  static const Color darkTextPrimary = Color(0xFFFFFFFF);
  static const Color darkTextSecondary = Color(0xFFCBD5E1);
  static const Color darkTextMuted = Color(0xFF94A3B8);

  // Pure clean Light (White theme)
  static const Color lightBackground = Color(0xFFF8FAFC);
  static const Color lightBackgroundElevated = Color(0xFFFFFFFF);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightSurfaceElevated = Color(0xFFF1F5F9);
  static const Color lightSurfaceBorder = Color(0xFFE2E8F0);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569);
  static const Color lightTextMuted = Color(0xFF64748B);

  // Default constants for backward compatibility (dark by default)
  static const Color background = darkBackground;
  static const Color backgroundElevated = darkBackgroundElevated;
  static const Color surface = darkSurface;
  static const Color surfaceElevated = darkSurfaceElevated;
  static const Color surfaceBorder = darkSurfaceBorder;
  static const Color surfaceBorderGlow = Color(0xFF6366F1);
  static const Color textPrimary = darkTextPrimary;
  static const Color textSecondary = darkTextSecondary;
  static const Color textMuted = darkTextMuted;

  // Modern vibrant brand accents (work vibrantly in both themes)
  static const Color brandPrimary = Color(0xFF7C3AED); // Electric Purple
  static const Color brandIndigo = Color(0xFF6366F1);  // Indigo
  static const Color brandPink = Color(0xFFEC4899);    // Hot Pink
  static const Color brandCyan = Color(0xFF06B6D4);    // Neon Cyan
  static const Color brandBlue = Color(0xFF3B82F6);    // Azure Blue

  // Status & Economy Accents
  static const Color coinGold = Color(0xFFFFB800);
  static const Color coinGoldDark = Color(0xFFD97706);
  static const Color success = Color(0xFF10B981);
  static const Color danger = Color(0xFFEF4444);
  static const Color warning = Color(0xFFF59E0B);

  // Modern Gradients
  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFFEC4899)],
  );

  static const LinearGradient cyanBlueGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
  );

  static const LinearGradient vipGoldGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFD700), Color(0xFFFF8A00)],
  );

  static const LinearGradient darkCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF181C33), Color(0xFF111424)],
  );

  static const LinearGradient lightCardGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFFFFFFF), Color(0xFFF8FAFC)],
  );

  static const LinearGradient darkMeshGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF0B0D18), Color(0xFF080910)],
  );

  static const LinearGradient lightMeshGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFF8FAFC), Color(0xFFEEF2F6)],
  );

  // Backward-compatibility alias
  static const LinearGradient meshBackgroundGradient = darkMeshGradient;

  // Context-aware dynamic helpers for Black and White theme
  static bool isDark(BuildContext context) => Theme.of(context).brightness == Brightness.dark;
  static Color bg(BuildContext context) => isDark(context) ? darkBackground : lightBackground;
  static Color surf(BuildContext context) => isDark(context) ? darkSurface : lightSurface;
  static Color surfElevated(BuildContext context) => isDark(context) ? darkSurfaceElevated : lightSurfaceElevated;
  static Color border(BuildContext context) => isDark(context) ? darkSurfaceBorder : lightSurfaceBorder;
  static Color txtPrimary(BuildContext context) => isDark(context) ? darkTextPrimary : lightTextPrimary;
  static Color txtSecondary(BuildContext context) => isDark(context) ? darkTextSecondary : lightTextSecondary;
  static Color txtMuted(BuildContext context) => isDark(context) ? darkTextMuted : lightTextMuted;
  static LinearGradient cardGrad(BuildContext context) => isDark(context) ? darkCardGradient : lightCardGradient;
  static LinearGradient meshGrad(BuildContext context) => isDark(context) ? darkMeshGradient : lightMeshGradient;
}

class AppTheme {
  AppTheme._();

  static final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.system);

  static void cycleThemeMode() {
    switch (themeModeNotifier.value) {
      case ThemeMode.system:
        themeModeNotifier.value = ThemeMode.dark;
        break;
      case ThemeMode.dark:
        themeModeNotifier.value = ThemeMode.light;
        break;
      case ThemeMode.light:
        themeModeNotifier.value = ThemeMode.system;
        break;
    }
  }

  static void setThemeMode(ThemeMode mode) {
    themeModeNotifier.value = mode;
  }

  static ThemeData get darkTheme {
    final baseTextTheme = GoogleFonts.interTextTheme(ThemeData.dark().textTheme);

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.darkBackground,
      primaryColor: AppColors.brandPrimary,
      cardColor: AppColors.darkSurface,
      dialogBackgroundColor: AppColors.darkSurface,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.brandIndigo,
        secondary: AppColors.brandPink,
        tertiary: AppColors.coinGold,
        surface: AppColors.darkSurface,
        error: AppColors.danger,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.darkTextPrimary,
        onError: Colors.white,
      ),
      textTheme: baseTextTheme.copyWith(
        displayLarge: baseTextTheme.displayLarge?.copyWith(
          color: AppColors.darkTextPrimary,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
        headlineMedium: baseTextTheme.headlineMedium?.copyWith(
          color: AppColors.darkTextPrimary,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          color: AppColors.darkTextPrimary,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(
          color: AppColors.darkTextPrimary,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          color: AppColors.darkTextSecondary,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: Colors.white),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 4,
          shadowColor: AppColors.brandIndigo.withOpacity(0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.darkSurfaceBorder, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.darkSurfaceBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.darkSurfaceBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.brandIndigo, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  static ThemeData get lightTheme {
    final baseTextTheme = GoogleFonts.interTextTheme(ThemeData.light().textTheme);

    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: AppColors.lightBackground,
      primaryColor: AppColors.brandPrimary,
      cardColor: AppColors.lightSurface,
      dialogBackgroundColor: AppColors.lightSurface,
      colorScheme: const ColorScheme.light(
        primary: AppColors.brandIndigo,
        secondary: AppColors.brandPink,
        tertiary: AppColors.coinGold,
        surface: AppColors.lightSurface,
        error: AppColors.danger,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: AppColors.lightTextPrimary,
        onError: Colors.white,
      ),
      textTheme: baseTextTheme.copyWith(
        displayLarge: baseTextTheme.displayLarge?.copyWith(
          color: AppColors.lightTextPrimary,
          fontWeight: FontWeight.bold,
          letterSpacing: -0.5,
        ),
        headlineMedium: baseTextTheme.headlineMedium?.copyWith(
          color: AppColors.lightTextPrimary,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          color: AppColors.lightTextPrimary,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(
          color: AppColors.lightTextPrimary,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          color: AppColors.lightTextSecondary,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: true,
        iconTheme: IconThemeData(color: AppColors.lightTextPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 2,
          shadowColor: AppColors.brandIndigo.withOpacity(0.25),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: GoogleFonts.inter(
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.lightSurfaceBorder, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.lightSurfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.lightSurfaceBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.lightSurfaceBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.brandIndigo, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}
