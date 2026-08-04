import 'package:flutter/material.dart';

abstract final class AppTheme {
  static const _seed = Color(0xFF6CE5B1);

  static ThemeData get dark => ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
      surface: const Color(0xFF111714),
    ),
    scaffoldBackgroundColor: const Color(0xFF090D0B),
    cardTheme: const CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: Color(0xFF111714),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      border: OutlineInputBorder(borderSide: BorderSide.none),
    ),
  );

  static ThemeData get light => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: _seed),
  );
}
