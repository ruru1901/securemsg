import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  // Color palette
  static const bg0 = Color(0xFF0A0A0F);       // deepest bg
  static const bg1 = Color(0xFF111118);       // primary bg
  static const bg2 = Color(0xFF1A1A24);       // card bg
  static const bg3 = Color(0xFF222230);       // elevated
  static const accent = Color(0xFF4F8EF7);    // blue accent
  static const accentDim = Color(0xFF2A4A8A); // dim accent
  static const success = Color(0xFF2ECC71);   // delivered/seen
  static const danger = Color(0xFFE74C3C);    // error
  static const textPrimary = Color(0xFFEEEEF5);
  static const textSecondary = Color(0xFF8888AA);
  static const textDim = Color(0xFF444460);
  static const border = Color(0xFF2A2A3A);

  static ThemeData dark() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg1,
      primaryColor: accent,
      colorScheme: const ColorScheme.dark(
        primary: accent,
        secondary: accentDim,
        surface: bg2,
        error: danger,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bg1,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(color: textSecondary),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: textPrimary, fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5),
        headlineMedium: TextStyle(color: textPrimary, fontSize: 22, fontWeight: FontWeight.w600, letterSpacing: -0.3),
        titleLarge: TextStyle(color: textPrimary, fontSize: 17, fontWeight: FontWeight.w600),
        titleMedium: TextStyle(color: textPrimary, fontSize: 15, fontWeight: FontWeight.w500),
        bodyLarge: TextStyle(color: textPrimary, fontSize: 15, height: 1.5),
        bodyMedium: TextStyle(color: textSecondary, fontSize: 13, height: 1.4),
        labelSmall: TextStyle(color: textDim, fontSize: 11, letterSpacing: 0.5),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: bg2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accent, width: 1.5),
        ),
        hintStyle: const TextStyle(color: textDim),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dividerColor: border,
      iconTheme: const IconThemeData(color: textSecondary),
    );
  }
}
