import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import 'constants.dart';

/// Load the user's fuel type list. Absence (or an empty list) means the
/// seeded default — it is never persisted just to exist.
Future<List<String>> loadFuelTypes() async {
  final prefs = await SharedPreferences.getInstance();
  final types = prefs.getStringList(kFuelTypesKey);
  if (types == null || types.isEmpty) return [kDefaultFuelType];
  return types;
}

/// Persist the full list (used by rename/delete and Drive restore).
Future<void> saveFuelTypes(List<String> types) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(kFuelTypesKey, types);
}

/// Add a fuel type. Returns false when the name is empty or a
/// case-insensitive duplicate of an existing type.
Future<bool> addFuelType(String name) async {
  final trimmed = name.trim();
  if (trimmed.isEmpty) return false;
  final types = await loadFuelTypes();
  final lower = trimmed.toLowerCase();
  if (types.any((t) => t.toLowerCase() == lower)) return false;
  types.add(trimmed);
  await saveFuelTypes(types);
  return true;
}

/// Rename a fuel type in place (list position preserved) and update every
/// existing log referencing it. Returns the number of updated logs, or -1
/// when the rename was rejected (empty target or duplicate of another type).
Future<int> renameFuelType(String from, String to) async {
  final trimmed = to.trim();
  if (trimmed.isEmpty || trimmed == from) return -1;
  final types = await loadFuelTypes();
  final idx = types.indexOf(from);
  if (idx == -1) return -1;
  final lower = trimmed.toLowerCase();
  for (var i = 0; i < types.length; i++) {
    if (i != idx && types[i].toLowerCase() == lower) return -1;
  }
  types[idx] = trimmed;
  await saveFuelTypes(types);
  return DatabaseHelper().renameFuelType(from, trimmed);
}

/// Remove a fuel type from the offered list. Existing logs keep the string —
/// delete means "stop offering this", not "erase history". The caller guards
/// against deleting the last remaining type.
Future<void> deleteFuelType(String name) async {
  final types = await loadFuelTypes();
  types.remove(name);
  await saveFuelTypes(types);
}
