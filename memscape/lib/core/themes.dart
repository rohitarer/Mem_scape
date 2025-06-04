import 'package:flutter/material.dart';

class AppTheme {
  // Color palette
  static const Color primaryColor = Color(0xFF6A1B9A);     // Deep Purple
  static const Color accentColor = Color(0xFFB39DDB);      // Lavender
  static const Color backgroundLight = Color(0xFFF9F8FD);  // Soft White
  static const Color textColor = Color(0xFF1C1C1C);         // Dark Gray

  // Dark mode colors
  static const Color backgroundDark = Color(0xFF121212);    // Dark scaffold
  static const Color textColorDark = Color(0xFFF9F8FD);      // Inverted text

  static ThemeData lightTheme = ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: backgroundLight,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryColor,
      primary: primaryColor,
      secondary: accentColor,
      background: backgroundLight,
      surface: Colors.white,
      onPrimary: Colors.white,
      onSecondary: textColor,
      onSurface: textColor,
      onBackground: textColor,
      brightness: Brightness.light,
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: textColor),
      bodyMedium: TextStyle(color: textColor),
    ),
    useMaterial3: true,
  );

  static ThemeData darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: backgroundDark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryColor,
      primary: primaryColor,
      secondary: accentColor,
      background: backgroundDark,
      surface: Colors.grey[900]!,
      onPrimary: Colors.white,
      onSecondary: Colors.white70,
      onSurface: Colors.white70,
      onBackground: Colors.white70,
      brightness: Brightness.dark,
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: textColorDark),
      bodyMedium: TextStyle(color: textColorDark),
    ),
    useMaterial3: true,
  );
}
