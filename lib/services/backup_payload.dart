import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../models/fuel_log.dart';
import '../utils/constants.dart';
import '../utils/fuel_type_manager.dart';
import '../utils/pump_brand_manager.dart';

/// Sentinel validated on restore so a foreign backup file is rejected.
const kBackupApp = 'fuelpulse';
// v2 added pumpBrands. Restore tolerates its absence, so v1 files still load.
const kBackupVersion = 2;

/// Snapshot everything worth backing up: all logs (including their costs),
/// the fuel type and pump brand lists, and the settings prefs. Callers must
/// await this BEFORE the first network await of an upload, so a concurrent
/// "Delete all data" can't land in the sign-in window and get uploaded as
/// the newest backup.
Future<Map<String, dynamic>> buildBackupPayload() async {
  final logs = await DatabaseHelper().getAllLogsChrono();
  final fuelTypes = await loadFuelTypes();
  final pumpBrands = await loadPumpBrands();
  final prefs = await SharedPreferences.getInstance();
  return {
    'app': kBackupApp,
    'version': kBackupVersion,
    'logs': logs.map((l) => l.toMap()).toList(),
    'fuelTypes': fuelTypes,
    'pumpBrands': pumpBrands,
    'settings': {
      'tankCapacity': prefs.getDouble(kTankCapacityKey),
      'themeAccent': prefs.getString(kThemeAccentKey),
      'themeLight': prefs.getString(kThemeLightKey),
    },
  };
}

/// Restore a payload produced by [buildBackupPayload].
///
/// Merge: logs are inserted keyed by id (ConflictAlgorithm.replace), so
/// re-restoring is idempotent and device-only entries survive. Settings,
/// fuel types and pump brands are NOT touched — merge means "existing wins".
/// Replace: local logs are wiped first, and settings + fuel types + pump
/// brands from the backup are applied.
///
/// All logs are parsed up front — one malformed entry rejects the whole file
/// before any state changes. Returns the number of restored logs.
Future<int> restoreBackup(Map<String, dynamic> data,
    {required bool replace}) async {
  if (data['app'] != kBackupApp || data['logs'] is! List) {
    throw const FormatException('Not a FuelPulse backup file.');
  }

  final List<FuelLog> logs;
  try {
    logs = (data['logs'] as List)
        .map((m) => FuelLog.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList();
  } catch (e) {
    throw FormatException('Backup contains a malformed entry: $e');
  }

  final db = DatabaseHelper();
  if (replace) {
    await db.deleteAllLogs();
  }
  await db.insertLogs(logs);

  if (replace) {
    final prefs = await SharedPreferences.getInstance();

    final settings = data['settings'];
    if (settings is Map) {
      final cap = settings['tankCapacity'];
      if (cap is num && cap > 0) {
        await prefs.setDouble(kTankCapacityKey, cap.toDouble());
      } else {
        await prefs.remove(kTankCapacityKey);
      }
      final accent = settings['themeAccent'];
      final light = settings['themeLight'];
      if (accent is String && light is String) {
        await prefs.setString(kThemeAccentKey, accent);
        await prefs.setString(kThemeLightKey, light);
      }
    }

    final types = data['fuelTypes'];
    if (types is List && types.isNotEmpty) {
      await saveFuelTypes(types.map((t) => t.toString()).toList());
    }

    final brands = data['pumpBrands'];
    if (brands is List && brands.isNotEmpty) {
      await savePumpBrands(brands.map((b) => b.toString()).toList());
    }
  }

  return logs.length;
}
