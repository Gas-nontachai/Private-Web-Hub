import 'package:flutter/material.dart';

/// Palette and shapes copied from the extension's popup.css.
class Palette {
  static const body = Color(0xFF0E2F80);
  static const panel = Color(0xFF153D9B);
  static const accent = Color(0xFFFFD52A);
  static const accentSoft = Color(0xFFFFF9D9);
  static const ink = Color(0xFF173A86);
  static const mark = Color(0xFF173D9D);
  static const markHover = Color(0xFF143B96);
  static const muted = Color(0xFF6D7F9F);
}

ThemeData buildTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: Palette.panel,
        brightness: Brightness.dark,
      ).copyWith(
        primary: Palette.accent,
        onPrimary: Palette.markHover,
        surface: Palette.body,
        onSurface: Colors.white,
        surfaceContainer: Palette.panel,
      );
  return ThemeData(
    useMaterial3: true,
    fontFamily: 'Kanit',
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.body,
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.panel,
      foregroundColor: Colors.white,
      titleTextStyle: TextStyle(
        fontFamily: 'Kanit',
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: Colors.white,
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Palette.accent,
      linearTrackColor: Palette.panel,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) =>
            s.contains(WidgetState.selected) ? Palette.accent : Colors.white70,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Palette.mark : Palette.panel,
      ),
    ),
    dividerColor: const Color(0x1FFFFFFF),
  );
}
