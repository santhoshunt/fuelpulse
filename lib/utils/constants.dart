import 'package:flutter/material.dart';

// ── SharedPreferences keys ───────────────────────────────────────────
// Appearance keys live in appearance_prefs.dart. The pre-v2.2.0 accent keys
// ('fuel_theme_accent', 'fuel_theme_light') are left on the phone, unread.
const String kTankCapacityKey = 'fuel_tank_cap';
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
// Mileage drop alert: the drop below average that raises it, in percent
// (0 is off), and per vehicle the closing time of the tank last dismissed.
const String kMileageAlertKey = 'fuel_mileage_alert_percent';
const int kMileageAlertDefault = 15;
String mileageAlertDismissedKey(String vehicleId) =>
    'fuel_mileage_alert_dismissed_$vehicleId';

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

