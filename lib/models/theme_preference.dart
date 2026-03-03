import 'package:flutter/material.dart';

class ThemePreference {
  final String accent;
  final String light;
  final String rgb;

  const ThemePreference({
    required this.accent,
    required this.light,
    required this.rgb,
  });

  /// Create from a single hex accent color, deriving light and rgb variants.
  factory ThemePreference.fromAccent(String accentHex) {
    final color = hexToColor(accentHex);
    final lightColor = Color.lerp(color, Colors.white, 0.3)!;
    final lightHex = '#${lightColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
    final r = (color.r * 255.0).round().clamp(0, 255);
    final g = (color.g * 255.0).round().clamp(0, 255);
    final b = (color.b * 255.0).round().clamp(0, 255);
    final rgb = '$r,$g,$b';
    return ThemePreference(accent: accentHex, light: lightHex, rgb: rgb);
  }

  /// Create from accent + light hex pair (used for presets).
  factory ThemePreference.fromPair(String accentHex, String lightHex) {
    final color = hexToColor(accentHex);
    final r = (color.r * 255.0).round().clamp(0, 255);
    final g = (color.g * 255.0).round().clamp(0, 255);
    final b = (color.b * 255.0).round().clamp(0, 255);
    final rgb = '$r,$g,$b';
    return ThemePreference(accent: accentHex, light: lightHex, rgb: rgb);
  }

  Color get accentColor => hexToColor(accent);
  Color get lightColor => hexToColor(light);

  static Color hexToColor(String hex) {
    hex = hex.replaceFirst('#', '');
    if (hex.length == 6) hex = 'FF$hex';
    return Color(int.parse(hex, radix: 16));
  }

  static const defaultAccent = '#FFD60A';
  static const defaultLight = '#FFE455';

  static ThemePreference get defaults =>
      const ThemePreference(accent: defaultAccent, light: defaultLight, rgb: '255,214,10');
}
