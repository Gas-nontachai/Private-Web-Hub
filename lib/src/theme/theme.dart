import 'package:flutter/material.dart';

import 'design_tokens.dart';
export 'design_tokens.dart';

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
    fontFamily: Design.fontFamily,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.body,
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.panel,
      foregroundColor: Colors.white,
      titleTextStyle: TextStyle(
        fontFamily: Design.fontFamily,
        fontSize: Design.headingSize,
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
    dividerColor: Palette.border,
  );
}
