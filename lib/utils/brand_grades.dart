import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import 'constants.dart';

/// Brands and the fuel grades each sells, as JSON `{brand: [grade, ...]}`,
/// in display order. Replaces the separate pump brand and fuel type lists
/// of v2.x, which stay in prefs untouched as the seed source.
const kBrandGradesKey = 'fuel_brand_grades';

/// What the six known brands sell at the pump.
const _knownGrades = {
  'Bharat Petroleum': ['E20', 'Speed', 'Speed 97', 'Speed 100'],
  'HP': ['E20', 'Power', 'Power 95', 'Power 99', 'Power 100'],
  'Indian Oil': ['E20', 'XP95', 'XP100'],
  'Jio-BP': ['E20', 'Active'],
  'Nayara Energy': ['E20'],
  'Shell': ['E20', 'V-Power'],
};

/// Grades for a brand nobody has described yet.
const kNewBrandGrades = [kDefaultFuelType];

/// The map for [brands] and [fuelTypes] from a v2.x install or a format 1
/// to 3 backup: each brand gets every old fuel type, then its known grades
/// it lacks. Old types come first so an upgrade keeps the grade the form
/// pre-selects ("Normal" for most) and old fill-ups keep a matching grade.
Map<String, List<String>> seedBrandGrades(
    List<String> brands, List<String> fuelTypes) {
  return {
    for (final b in brands)
      b: {
        ...fuelTypes,
        ...?_knownGrades[b],
      }.toList(),
  };
}

/// The saved map, seeded and saved on first read from the v2.x lists.
Future<Map<String, List<String>>> loadBrandGrades() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(kBrandGradesKey);
  if (raw != null) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final map = {
        for (final e in decoded.entries)
          e.key: (e.value as List).map((g) => '$g').toList(),
      };
      if (map.isNotEmpty) return map;
    } catch (_) {}
  }
  final brands = prefs.getStringList(kPumpBrandsKey);
  final types = prefs.getStringList(kFuelTypesKey);
  final seeded = seedBrandGrades(
    brands == null || brands.isEmpty ? List.of(kDefaultPumpBrands) : brands,
    types == null || types.isEmpty ? const [kDefaultFuelType] : types,
  );
  await saveBrandGrades(seeded);
  return seeded;
}

Future<void> saveBrandGrades(Map<String, List<String>> map) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kBrandGradesKey, jsonEncode(map));
}

/// Every grade across brands, first appearance first (for the format 3
/// backup's `fuelTypes`).
List<String> allGrades(Map<String, List<String>> map) =>
    {for (final g in map.values) ...g}.toList();

bool _taken(Iterable<String> names, String name, {String? except}) {
  final lower = name.toLowerCase();
  return names.any((n) => n != except && n.toLowerCase() == lower);
}

/// Adds a brand with its known grades, or [kNewBrandGrades]. False when
/// the name is empty or taken, ignoring case.
Future<bool> addBrand(String name) async {
  final trimmed = name.trim();
  final map = await loadBrandGrades();
  if (trimmed.isEmpty || _taken(map.keys, trimmed)) return false;
  map[trimmed] = List.of(_knownGrades[trimmed] ?? kNewBrandGrades);
  await saveBrandGrades(map);
  return true;
}

/// Renames a brand in place, on every log and every pump. Returns the
/// number of logs updated, or -1 when the name is empty or taken.
Future<int> renameBrand(String from, String to) async {
  final trimmed = to.trim();
  final map = await loadBrandGrades();
  if (trimmed.isEmpty ||
      trimmed == from ||
      !map.containsKey(from) ||
      _taken(map.keys, trimmed, except: from)) {
    return -1;
  }
  await saveBrandGrades(
      {for (final e in map.entries) e.key == from ? trimmed : e.key: e.value});
  return DatabaseHelper().renamePumpBrand(from, trimmed);
}

/// Stops offering a brand. Logs and pumps keep it. The caller keeps at
/// least one brand.
Future<void> deleteBrand(String name) async {
  final map = await loadBrandGrades();
  map.remove(name);
  await saveBrandGrades(map);
}

/// Adds a grade to one brand. False when empty or already there.
Future<bool> addGrade(String brand, String grade) async {
  final trimmed = grade.trim();
  final map = await loadBrandGrades();
  final grades = map[brand];
  if (grades == null || trimmed.isEmpty || _taken(grades, trimmed)) {
    return false;
  }
  grades.add(trimmed);
  await saveBrandGrades(map);
  return true;
}

/// Renames one brand's grade, and the grade on that brand's logs. Returns
/// the number of logs updated, or -1 when the name is empty or taken.
Future<int> renameGrade(String brand, String from, String to) async {
  final trimmed = to.trim();
  final map = await loadBrandGrades();
  final grades = map[brand];
  final i = grades?.indexOf(from) ?? -1;
  if (grades == null ||
      i < 0 ||
      trimmed.isEmpty ||
      trimmed == from ||
      _taken(grades, trimmed, except: from)) {
    return -1;
  }
  grades[i] = trimmed;
  await saveBrandGrades(map);
  return DatabaseHelper().renameGrade(brand, from, trimmed);
}

/// Stops offering a grade for one brand; logs keep it. The caller keeps at
/// least one grade.
Future<void> deleteGrade(String brand, String grade) async {
  final map = await loadBrandGrades();
  map[brand]?.remove(grade);
  await saveBrandGrades(map);
}
