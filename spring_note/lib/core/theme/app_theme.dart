import 'package:flutter/material.dart';

class AppTheme {
  const AppTheme._();

  static const Color background = Color(0xFFFCFCFC);
  static const Color sidebar = Color(0xFFFCFCFC);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceMuted = Color(0xFFEDEDED);
  static const Color border = Color(0xFFE5E5E5);
  static const Color text = Color(0xFF171717);
  static const Color textMuted = Color(0xFF4F4F4F);
  static const Color textSubtle = Color(0xFF666666);

  static ThemeData light({String appFont = 'system'}) {
    final fontFamily = appFont.trim().isEmpty || appFont == 'system'
        ? 'Segoe UI'
        : appFont.trim();
    final colorScheme = ColorScheme.fromSeed(
      seedColor: text,
      brightness: Brightness.light,
      surface: surface,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme.copyWith(
        primary: text,
        secondary: textMuted,
        surface: surface,
      ),
      scaffoldBackgroundColor: background,
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      focusColor: Colors.transparent,
      fontFamily: fontFamily,
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          color: text,
          fontSize: 32,
          fontWeight: FontWeight.w600,
          height: 1.2,
        ),
        headlineMedium: TextStyle(
          color: text,
          fontSize: 24,
          fontWeight: FontWeight.w600,
          height: 1.25,
        ),
        titleLarge: TextStyle(
          color: text,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          height: 1.35,
        ),
        titleMedium: TextStyle(
          color: text,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          height: 1.4,
        ),
        bodyLarge: TextStyle(
          color: text,
          fontSize: 15,
          fontWeight: FontWeight.w400,
          height: 1.7,
        ),
        bodyMedium: TextStyle(
          color: textMuted,
          fontSize: 13,
          fontWeight: FontWeight.w400,
          height: 1.55,
        ),
        labelLarge: TextStyle(
          color: text,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ).apply(fontFamily: fontFamily),
      iconTheme: const IconThemeData(color: textMuted, size: 20),
      dividerTheme: const DividerThemeData(
        color: border,
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        hintStyle: const TextStyle(color: textSubtle),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: Color(0xFFCFCFCF)),
        ),
      ),
    );
  }

  static double fontScaleFactor(double fontScale) {
    final safeScale = fontScale.isFinite ? fontScale : 100;
    return safeScale.clamp(80, 140).toDouble() / 100;
  }
}
