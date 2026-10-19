import 'package:flutter/material.dart';
import '../models/theme_preference.dart';

// ── SharedPreferences keys ───────────────────────────────────────────
const String kTankCapacityKey = 'fuel_tank_cap';
const String kThemeAccentKey = 'fuel_theme_accent';
const String kThemeLightKey = 'fuel_theme_light';
const String kFuelTypesKey = 'fuel_fuel_types';
const String kPumpBrandsKey = 'fuel_pump_brands';
// Which vehicle Home, the fill-up form and Statistics show (vehicle id).
const String kActiveVehicleKey = 'fuel_active_vehicle';
// In-app updater: daily check switch, last check time, the tag answered
// with "Not now", and the tag an install was started for.
const String kUpdateOnLaunchKey = 'fuel_update_on_launch';
const String kUpdateLastCheckKey = 'fuel_update_last_check';
const String kUpdateDismissedKey = 'fuel_update_dismissed';
const String kUpdateInstallingKey = 'fuel_update_installing';

// ── Fuel types ───────────────────────────────────────────────────────
const String kDefaultFuelType = 'Normal';

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

/// Look up brand config by name (case-insensitive). Unknown custom brands
/// get a neutral badge with an initials abbreviation.
BrandConfig getBrandConfig(String brandName) {
  final trimmed = brandName.trim();
  final lower = trimmed.toLowerCase();
  for (final b in kBrands) {
    if (b.name.toLowerCase() == lower) return b;
  }
  // Alias matching
  if (lower == 'hindustan petroleum') return kBrands[1]; // HP
  if (lower.contains('nayara')) return kBrands[4];
  if (trimmed.isEmpty || lower == 'other') return kOtherBrand;
  final words = trimmed.split(RegExp(r'\s+'));
  final abbr = words.take(2).map((w) => w[0].toUpperCase()).join();
  return BrandConfig(
    name: trimmed,
    abbreviation: abbr,
    background: kOtherBrand.background,
    textColor: kOtherBrand.textColor,
  );
}

/// Seed list offered before the user customizes their pump brands.
final List<String> kDefaultPumpBrands =
    List.unmodifiable(kBrands.map((b) => b.name));

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
