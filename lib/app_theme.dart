import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class AppPalette {
  static const background = Color(0xFF000000);
  static const surface = Color(0xFF1C1C1E);
  static const surfaceElevated = Color(0xFF2C2C2E);
  static const surfaceMuted = Color(0xFF3A3A3C);
  static const separator = Color(0xFF38383A);

  static const blue = Color(0xFF0A84FF);
  static const blueContainer = Color(0xFF0A3D6D);
  static const cyan = Color(0xFF64D2FF);
  static const green = Color(0xFF30D158);
  static const greenContainer = Color(0xFF123D24);
  static const orange = Color(0xFFFF9F0A);
  static const red = Color(0xFFFF453A);
  static const redContainer = Color(0xFF4A1715);

  static const label = Color(0xFFFFFFFF);
  static const secondaryLabel = Color(0xFFAEAEB2);
  static const tertiaryLabel = Color(0xFF8E8E93);
}

abstract final class AppTheme {
  static final ColorScheme _scheme = const ColorScheme.dark(
    primary: AppPalette.blue,
    onPrimary: AppPalette.label,
    primaryContainer: AppPalette.blueContainer,
    onPrimaryContainer: Color(0xFFD9ECFF),
    secondary: AppPalette.cyan,
    onSecondary: AppPalette.label,
    secondaryContainer: Color(0xFF153F4C),
    onSecondaryContainer: Color(0xFFD7F5FF),
    tertiary: AppPalette.green,
    onTertiary: AppPalette.background,
    tertiaryContainer: AppPalette.greenContainer,
    onTertiaryContainer: Color(0xFFC8F7D4),
    error: AppPalette.red,
    onError: AppPalette.label,
    errorContainer: AppPalette.redContainer,
    onErrorContainer: Color(0xFFFFDAD7),
    surface: AppPalette.surface,
    onSurface: AppPalette.label,
    onSurfaceVariant: AppPalette.secondaryLabel,
    outline: AppPalette.surfaceMuted,
    outlineVariant: AppPalette.separator,
    shadow: AppPalette.background,
    scrim: AppPalette.background,
    inverseSurface: AppPalette.label,
    onInverseSurface: AppPalette.background,
    inversePrimary: Color(0xFF0066CC),
  );

  static ThemeData get dark {
    final baseTextTheme = GoogleFonts.interTextTheme(
      ThemeData.dark(useMaterial3: true).textTheme,
    ).apply(bodyColor: AppPalette.label, displayColor: AppPalette.label);

    final outlineBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide.none,
    );

    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: _scheme,
      scaffoldBackgroundColor: AppPalette.background,
      canvasColor: AppPalette.background,
      cardColor: AppPalette.surface,
      dividerColor: AppPalette.separator,
      splashColor: AppPalette.label.withValues(alpha: 0.08),
      highlightColor: AppPalette.label.withValues(alpha: 0.04),
      textTheme: baseTextTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: AppPalette.background,
        foregroundColor: AppPalette.label,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: AppPalette.label,
          letterSpacing: -0.4,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppPalette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppPalette.separator),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppPalette.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppPalette.surfaceElevated,
        labelStyle: const TextStyle(color: AppPalette.secondaryLabel),
        hintStyle: const TextStyle(color: AppPalette.tertiaryLabel),
        prefixIconColor: AppPalette.secondaryLabel,
        suffixIconColor: AppPalette.secondaryLabel,
        border: outlineBorder,
        enabledBorder: outlineBorder,
        focusedBorder: outlineBorder.copyWith(
          borderSide: const BorderSide(color: AppPalette.blue, width: 1.4),
        ),
        errorBorder: outlineBorder.copyWith(
          borderSide: const BorderSide(color: AppPalette.red),
        ),
        focusedErrorBorder: outlineBorder.copyWith(
          borderSide: const BorderSide(color: AppPalette.red, width: 1.4),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppPalette.blue,
          foregroundColor: AppPalette.label,
          disabledBackgroundColor: AppPalette.surfaceMuted,
          disabledForegroundColor: AppPalette.tertiaryLabel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppPalette.blue,
          foregroundColor: AppPalette.label,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: AppPalette.blue),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppPalette.blue,
        foregroundColor: AppPalette.label,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppPalette.surfaceElevated,
        contentTextStyle: const TextStyle(color: AppPalette.label),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppPalette.blue,
      ),
      dividerTheme: const DividerThemeData(
        color: AppPalette.separator,
        thickness: 0.6,
        space: 1,
      ),
    );
  }
}
