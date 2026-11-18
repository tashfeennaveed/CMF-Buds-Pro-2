import 'package:flutter/material.dart';

/// Minimal dark palette: neutral greys and one accent.
class Palette {
  static const bg = Color(0xFF111214);
  static const panel = Color(0xFF17181B);
  static const surface = Color(0xFF1E2024);
  static const line = Color(0xFF2B2E33);
  static const text = Color(0xFFECEDEF);
  static const muted = Color(0xFF8B8F97);
  static const accent = Color(0xFF6C9CFF);
  static const onAccent = Color(0xFF0B1220);
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: Palette.bg,
    colorScheme: base.colorScheme.copyWith(
      primary: Palette.accent,
      onPrimary: Palette.onAccent,
      surface: Palette.surface,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: Palette.text,
      displayColor: Palette.text,
    ),
    dividerColor: Palette.line,
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.all(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Palette.accent : Palette.line,
      ),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Palette.accent,
        foregroundColor: Palette.onAccent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Palette.text,
        side: const BorderSide(color: Palette.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Palette.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
