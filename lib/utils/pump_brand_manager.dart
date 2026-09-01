import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import 'constants.dart';

/// Load the user's pump brand list. Absence (or an empty list) means the
/// seeded defaults — they are never persisted just to exist.
Future<List<String>> loadPumpBrands() async {
  final prefs = await SharedPreferences.getInstance();
  final brands = prefs.getStringList(kPumpBrandsKey);
  if (brands == null || brands.isEmpty) return List.of(kDefaultPumpBrands);
  return brands;
}

/// Persist the full list (used by rename/delete and Drive restore).
Future<void> savePumpBrands(List<String> brands) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(kPumpBrandsKey, brands);
}

/// Add a pump brand. Returns false when the name is empty or a
/// case-insensitive duplicate of an existing brand.
Future<bool> addPumpBrand(String name) async {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return false;
  final brands = await loadPumpBrands();
  final lower = trimmed.toLowerCase();
  if (brands.any((b) => b.toLowerCase() == lower)) return false;
  brands.add(trimmed);
  await savePumpBrands(brands);
  return true;
}

/// Rename a pump brand in place (list position preserved) and update every
/// existing log referencing it. Returns the number of updated logs, or -1
/// when the rename was rejected (empty target or duplicate of another brand).
Future<int> renamePumpBrand(String from, String to) async {
  final trimmed = to.trim();
  if (trimmed.isEmpty || trimmed == from) return -1;
  final brands = await loadPumpBrands();
  final idx = brands.indexOf(from);
  if (idx == -1) return -1;
  final lower = trimmed.toLowerCase();
  for (var i = 0; i < brands.length; i++) {
    if (i != idx && brands[i].toLowerCase() == lower) return -1;
  }
  brands[idx] = trimmed;
  await savePumpBrands(brands);
  return DatabaseHelper().renamePumpBrand(from, trimmed);
}

/// Remove a pump brand from the offered list. Existing logs keep the string —
/// delete means "stop offering this", not "erase history". The caller guards
/// against deleting the last remaining brand.
Future<void> deletePumpBrand(String name) async {
  final brands = await loadPumpBrands();
  brands.remove(name);
  await savePumpBrands(brands);
}
