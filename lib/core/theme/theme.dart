import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const seed = Color(0xFF3F51B5); // Indigo base
  static final lightScheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.light,
  );

  static ThemeData light() {
    final base = ThemeData(
      colorScheme: lightScheme,
      useMaterial3: true,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      scaffoldBackgroundColor: lightScheme.surface,
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        showCloseIcon: true,
        backgroundColor: lightScheme.inverseSurface,
        contentTextStyle: TextStyle(color: lightScheme.onInverseSurface),
      ),
      cardTheme: CardThemeData(
        color: lightScheme.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        backgroundColor: lightScheme.surface,
        foregroundColor: lightScheme.onSurface,
        centerTitle: true,
      ),
      inputDecorationTheme: InputDecorationTheme(
        labelStyle: TextStyle(color: lightScheme.onSurfaceVariant),
  hintStyle: TextStyle(color: lightScheme.onSurfaceVariant.withValues(alpha: 0.7)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: lightScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: lightScheme.primary, width: 2),
        ),
        filled: true,
        fillColor: lightScheme.surfaceContainerLowest,
      ),
    );

    final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: lightScheme.onSurface,
      displayColor: lightScheme.onSurface,
    ).copyWith(
      headlineLarge: GoogleFonts.inter(fontWeight: FontWeight.w700, color: lightScheme.onSurface),
      headlineSmall: GoogleFonts.inter(fontWeight: FontWeight.w700, color: lightScheme.onSurface),
      titleLarge: GoogleFonts.inter(fontWeight: FontWeight.w600, color: lightScheme.onSurface),
      titleMedium: GoogleFonts.inter(fontWeight: FontWeight.w600, color: lightScheme.onSurface),
      bodyLarge: GoogleFonts.inter(fontWeight: FontWeight.w400, color: lightScheme.onSurface),
      bodyMedium: GoogleFonts.inter(fontWeight: FontWeight.w400, color: lightScheme.onSurface),
      labelLarge: GoogleFonts.inter(fontWeight: FontWeight.w600, color: lightScheme.onPrimary),
    );

    return base.copyWith(
      textTheme: textTheme,
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          foregroundColor: lightScheme.onPrimary,
          backgroundColor: lightScheme.primary,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          foregroundColor: lightScheme.primary,
          side: BorderSide(color: lightScheme.primary),
        ),
      ),
    );
  }
}
