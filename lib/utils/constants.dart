import 'package:flutter/material.dart';
import '../models/theme_preference.dart';

// ── SharedPreferences keys ───────────────────────────────────────────
const String kTankCapacityKey = 'fuel_tank_cap';
const String kThemeAccentKey = 'fuel_theme_accent';
const String kThemeLightKey = 'fuel_theme_light';

// ── Brand configuration ──────────────────────────────────────────────
class BrandConfig {
  final String name;
  final String abbreviation;
  final Color background;
  final Color textColor;

  const BrandConfig({
    required this.name,
    required this.abbreviation,
    required this.background,
    required this.textColor,
  });
}

final List<BrandConfig> kBrands = [
  BrandConfig(
    name: 'Shell',
    abbreviation: 'S',
    background: const Color(0xFFFBCE07),
    textColor: const Color(0xFFDD1D21),
  ),
  BrandConfig(
    name: 'HP',
    abbreviation: 'HP',
    background: const Color(0xFF00843D),
    textColor: Colors.white,
  ),
  BrandConfig(
    name: 'Indian Oil',
    abbreviation: 'IO',
    background: const Color(0xFFF26522),
    textColor: Colors.white,
  ),
  BrandConfig(
    name: 'Bharat Petroleum',
    abbreviation: 'BP',
    background: const Color(0xFF0054A6),
    textColor: Colors.white,
  ),
  BrandConfig(
    name: 'Nayara Energy',
    abbreviation: 'N',
    background: const Color(0xFFE31E24),
    textColor: Colors.white,
  ),
  BrandConfig(
    name: 'Jio-BP',
    abbreviation: 'JB',
    background: const Color(0xFF7B2D8E),
    textColor: Colors.white,
  ),
];

const BrandConfig kOtherBrand = BrandConfig(
  name: 'Other',
  abbreviation: '⛽',
  background: Color(0xFF4B5563),
  textColor: Colors.white,
);

/// Look up brand config by name (case-insensitive). Falls back to Other.
BrandConfig getBrandConfig(String brandName) {
  final lower = brandName.toLowerCase().trim();
  for (final b in kBrands) {
    if (b.name.toLowerCase() == lower) return b;
  }
  // Alias matching
  if (lower == 'hindustan petroleum') return kBrands[1]; // HP
  if (lower.contains('nayara')) return kBrands[4];
  return kOtherBrand;
}

/// Dropdown brand names including "Other".
final List<String> kBrandDropdownItems = [
  ...kBrands.map((b) => b.name),
  'Other',
];

// ── Theme presets ────────────────────────────────────────────────────
class ThemePresetSwatch {
  final String name;
  final String category;
  final String accent;
  final String light;

  const ThemePresetSwatch({
    required this.name,
    required this.category,
    required this.accent,
    required this.light,
  });

  ThemePreference toThemePreference() =>
      ThemePreference.fromPair(accent, light);
}

const List<ThemePresetSwatch> kThemePresets = [
  // Neon
  ThemePresetSwatch(name: 'Neon Green', category: 'Neon', accent: '#86F700', light: '#BDE30C'),
  ThemePresetSwatch(name: 'Neon Mint', category: 'Neon', accent: '#00FF87', light: '#34d399'),
  ThemePresetSwatch(name: 'Neon Cyan', category: 'Neon', accent: '#00F0FF', light: '#67E8F9'),
  ThemePresetSwatch(name: 'Neon Purple', category: 'Neon', accent: '#BF5AF2', light: '#D49DFF'),
  ThemePresetSwatch(name: 'Neon Pink', category: 'Neon', accent: '#FF2D55', light: '#FF6482'),
  ThemePresetSwatch(name: 'Neon Yellow', category: 'Neon', accent: '#FFD60A', light: '#FFE455'),
  ThemePresetSwatch(name: 'Neon Violet', category: 'Neon', accent: '#8F5FF8', light: '#B49AFF'),
  // Classic
  ThemePresetSwatch(name: 'Emerald', category: 'Classic', accent: '#10b981', light: '#34d399'),
  ThemePresetSwatch(name: 'Blue', category: 'Classic', accent: '#3B82F6', light: '#60A5FA'),
  ThemePresetSwatch(name: 'Orange', category: 'Classic', accent: '#F97316', light: '#FB923C'),
  ThemePresetSwatch(name: 'Red', category: 'Classic', accent: '#EF4444', light: '#F87171'),
  ThemePresetSwatch(name: 'Pink', category: 'Classic', accent: '#EC4899', light: '#F472B6'),
  ThemePresetSwatch(name: 'White', category: 'Classic', accent: '#FFFFFF', light: '#E0E0E0'),
];

// ── App-wide colors ──────────────────────────────────────────────────
const Color kBgBase = Color(0xFF080808);
const Color kBgSurface = Color(0x0AFFFFFF); // ~4% white
const Color kTextPrimary = Color(0xFFE8EDF5);
const Color kTextSecondary = Color(0xFF8B95A8);
const Color kTextMuted = Color(0xFF4B5563);
const Color kDanger = Color(0xFFEF4444);
