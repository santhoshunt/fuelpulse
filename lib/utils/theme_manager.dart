import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/theme_preference.dart';
import 'constants.dart';

/// Load saved theme preference from SharedPreferences.
Future<ThemePreference> loadTheme() async {
  final prefs = await SharedPreferences.getInstance();
  final accent = prefs.getString(kThemeAccentKey);
  final light = prefs.getString(kThemeLightKey);
  if (accent != null && light != null) {
    return ThemePreference.fromPair(accent, light);
  }
  return ThemePreference.defaults;
}

/// Save theme preference to SharedPreferences.
Future<void> saveTheme(ThemePreference theme) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kThemeAccentKey, theme.accent);
  await prefs.setString(kThemeLightKey, theme.light);
}

/// Build full ThemeData from a ThemePreference.
ThemeData buildThemeData(ThemePreference theme) {
  final accent = theme.accentColor;
  final light = theme.lightColor;

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: kBgBase,
    colorScheme: ColorScheme.dark(
      primary: accent,
      secondary: light,
      surface: const Color(0xFF121212),
      error: kDanger,
      onPrimary: _contrastText(accent),
      onSecondary: _contrastText(light),
      onSurface: kTextPrimary,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: kBgBase,
      foregroundColor: kTextPrimary,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: Colors.white.withValues(alpha: 0.05),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: accent,
      foregroundColor: _contrastText(accent),
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.05),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
      labelStyle: TextStyle(color: kTextSecondary),
      hintStyle: TextStyle(color: kTextMuted),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return accent;
        return kTextMuted;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return accent.withValues(alpha: 0.35);
        }
        return Colors.white.withValues(alpha: 0.1);
      }),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: _contrastText(accent),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        elevation: 4,
        shadowColor: accent.withValues(alpha: 0.4),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: accent,
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFF1A1A1A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF1E1E1E),
      contentTextStyle: const TextStyle(color: kTextPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dividerTheme: DividerThemeData(
      color: Colors.white.withValues(alpha: 0.08),
      thickness: 1,
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
      ),
    ),
  );
}

/// Return black or white text color based on luminance of the background.
Color _contrastText(Color bg) {
  return bg.computeLuminance() > 0.5 ? Colors.black : Colors.white;
}
