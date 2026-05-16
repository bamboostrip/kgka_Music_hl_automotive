import 'package:flutter/material.dart';

class AppTheme {
  static const blue = Color(0xFF1478FF);
  static const musicRed = Color(0xFFFF2D55);

  static ThemeData light() {
    return _theme(Brightness.light);
  }

  static ThemeData dark() {
    return _theme(Brightness.dark);
  }

  static ThemeData _theme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(seedColor: blue, brightness: brightness)
        .copyWith(
          primary: isDark ? const Color(0xFF68AEFF) : blue,
          secondary: musicRed,
          tertiary: const Color(0xFF24C768),
          surface: isDark ? const Color(0xFF0B0C10) : Colors.white,
          surfaceContainerLowest: isDark
              ? const Color(0xFF06070A)
              : Colors.white,
          surfaceContainer: isDark
              ? const Color(0xFF151820)
              : const Color(0xFFF4F7FB),
          surfaceContainerHighest: isDark
              ? const Color(0xFF202430)
              : const Color(0xFFEFF5FF),
          onSurface: isDark ? Colors.white : const Color(0xFF080B12),
          onSurfaceVariant: isDark
              ? const Color(0xFFB0B8C6)
              : const Color(0xFF6F7785),
          outline: isDark ? const Color(0xFF4D5668) : const Color(0xFFD2DAE7),
          outlineVariant: isDark
              ? const Color(0xFF303747)
              : const Color(0xFFE7EDF7),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? const Color(0xFF06070A) : Colors.white,
      fontFamilyFallback: const [
        'SF Pro Display',
        'SF Pro Text',
        'Roboto',
        'Arial',
      ],
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          highlightColor: scheme.primary.withValues(alpha: .08),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 44),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
          shape: const StadiumBorder(),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF171A22) : Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: .72),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 1.3),
        ),
      ),
    );
  }
}
