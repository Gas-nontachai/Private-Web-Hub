import 'package:flutter/material.dart';

import 'design_tokens.dart';
export 'design_tokens.dart';

ThemeData buildTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: Palette.appSurface,
        brightness: Brightness.dark,
      ).copyWith(
        primary: Palette.appText,
        onPrimary: Palette.appBackground,
        surface: Palette.appBackground,
        onSurface: Palette.appText,
        surfaceContainer: Palette.appSurface,
        secondary: Palette.appTextMuted,
      );
  return ThemeData(
    useMaterial3: true,
    fontFamily: Design.fontFamily,
    colorScheme: scheme,
    scaffoldBackgroundColor: Palette.appBackground,
    appBarTheme: const AppBarTheme(
      backgroundColor: Palette.appBackground,
      foregroundColor: Palette.appText,
      titleTextStyle: TextStyle(
        fontFamily: Design.fontFamily,
        fontSize: Design.headingSize,
        fontWeight: FontWeight.w600,
        color: Palette.appText,
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: Palette.appText,
      linearTrackColor: Palette.appSurface,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? Palette.appText
            : Palette.appTextMuted,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? Palette.appSurfaceActive
            : Palette.appSurface,
      ),
    ),
    dividerColor: Palette.border,
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Palette.appSurface,
      indicatorColor: Palette.appSurfaceActive,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? Palette.appText
              : Palette.appTextMuted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          color: states.contains(WidgetState.selected)
              ? Palette.appText
              : Palette.appTextMuted,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.appSurface,
      hintStyle: const TextStyle(color: Palette.appTextMuted),
      prefixIconColor: Palette.appTextMuted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(40),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(40),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(40),
        borderSide: const BorderSide(color: Palette.appTextMuted),
      ),
    ),
  );
}
