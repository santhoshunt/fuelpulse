import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../models/fuel_log.dart';
import '../models/vehicle.dart';
import '../utils/constants.dart';
import '../utils/fuel_type_manager.dart';
import '../utils/pump_brand_manager.dart';
import '../utils/vehicle_manager.dart';

/// Sentinel validated on restore so a foreign backup file is rejected.
const kBackupApp = 'fuelpulse';
// v2 added pumpBrands; v3 added vehicles and moved tank capacity onto them.
// Restore tolerates every older shape, and refuses a newer one.
const kBackupVersion = 3;

/// Snapshot everything worth backing up: every vehicle and all their logs
/// (including costs), the fuel type and pump brand lists, and the settings
/// prefs. Callers must await this BEFORE the first network await of an
/// upload, so a concurrent "Delete all data" can't land in the sign-in
/// window and get uploaded as the newest backup.
Future<Map<String, dynamic>> buildBackupPayload() async {
  final db = DatabaseHelper();
  final logs = await db.getEveryLogChrono();
  final vehicles = await db.getVehicles();
  final fuelTypes = await loadFuelTypes();
  final pumpBrands = await loadPumpBrands();
  final prefs = await SharedPreferences.getInstance();
  return {
    'app': kBackupApp,
    'version': kBackupVersion,
    'vehicles': vehicles.map((v) => v.toMap()).toList(),
    'logs': logs.map((l) => l.toMap()).toList(),
    'fuelTypes': fuelTypes,
    'pumpBrands': pumpBrands,
    'settings': {
      'activeVehicleId': prefs.getString(kActiveVehicleKey),
      'themeAccent': prefs.getString(kThemeAccentKey),
      'themeLight': prefs.getString(kThemeLightKey),
    },
  };
}

/// Restore a payload produced by [buildBackupPayload], or by an older
/// FuelPulse (v1/v2 files have no vehicles: their logs go to the default
/// vehicle, and a replace gives it the file's tank capacity).
///
/// Merge: vehicles and logs are inserted keyed by id, so re-restoring is
/// idempotent and device-only entries survive. A log whose vehicle is on
/// neither side goes to the default vehicle. Settings, fuel types and pump
/// brands are NOT touched: merge means "existing wins".
/// Replace: every local vehicle and log is swapped for the file's in one
/// transaction, and settings + fuel types + pump brands are applied.
///
/// Everything is parsed up front: one malformed entry rejects the whole
/// file before any state changes. Returns the number of restored logs.
Future<int> restoreBackup(Map<String, dynamic> data,
    {required bool replace}) async {
  if (data['app'] != kBackupApp || data['logs'] is! List) {
    throw const FormatException('Not a FuelPulse backup file.');
  }
  final version = data['version'];
  if (version is int && version > kBackupVersion) {
    throw const FormatException(
        'This backup was made by a newer FuelPulse. Update the app, then '
        'restore.');
  }

  List<FuelLog> logs;
  try {
    logs = (data['logs'] as List)
        .map((m) => FuelLog.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList();
  } catch (e) {
    throw FormatException('Backup contains a malformed entry: $e');
  }

  // Null for a v1/v2 file, which predates vehicles.
  List<Vehicle>? fileVehicles;
  final rawVehicles = data['vehicles'];
  if (rawVehicles != null) {
    try {
      fileVehicles = (rawVehicles as List)
          .map((m) => Vehicle.fromMap(Map<String, dynamic>.from(m as Map)))
          .toList();
    } catch (e) {
      throw FormatException('Backup contains a malformed vehicle: $e');
    }
  }

  final db = DatabaseHelper();
  final settings = data['settings'] is Map ? data['settings'] as Map : null;

  if (replace) {
    final vehicles = List.of(fileVehicles ?? const <Vehicle>[]);
    final ids = vehicles.map((v) => v.id).toSet();
    logs = _ownedBy(logs, ids.isEmpty ? {kDefaultVehicleId} : ids);
    // The default vehicle is added when the file has no vehicles (v1/v2)
    // or some log was moved to it by [_ownedBy].
    final needsDefault = vehicles.isEmpty ||
        logs.any((l) => l.vehicleId == kDefaultVehicleId);
    if (needsDefault && !ids.contains(kDefaultVehicleId)) {
      vehicles.add(DatabaseHelper.defaultVehicle(sortOrder: vehicles.length));
    }
    await db.replaceAllData(vehicles, logs);

    final prefs = await SharedPreferences.getInstance();
    // Pre-vehicle tank capacity belongs to the default vehicle now.
    await prefs.remove(kTankCapacityKey);

    if (settings != null) {
      final cap = settings['tankCapacity'];
      if (fileVehicles == null && cap is num && cap > 0) {
        final v = await db.getVehicle(kDefaultVehicleId);
        if (v != null) {
          await db.updateVehicle(v.copyWith(tankCapacity: cap.toDouble()));
        }
      }
      final active = settings['activeVehicleId'];
      if (active is String && await db.getVehicle(active) != null) {
        await setActiveVehicle(active);
      } else {
        await prefs.remove(kActiveVehicleKey);
      }
      final accent = settings['themeAccent'];
      final light = settings['themeLight'];
      if (accent is String && light is String) {
        await prefs.setString(kThemeAccentKey, accent);
        await prefs.setString(kThemeLightKey, light);
      }
    } else {
      await prefs.remove(kActiveVehicleKey);
    }

    final types = data['fuelTypes'];
    if (types is List && types.isNotEmpty) {
      await saveFuelTypes(types.map((t) => t.toString()).toList());
    }

    final brands = data['pumpBrands'];
    if (brands is List && brands.isNotEmpty) {
      await savePumpBrands(brands.map((b) => b.toString()).toList());
    }
  } else {
    final deviceIds = (await db.getVehicles()).map((v) => v.id).toSet();
    final newVehicles = [
      for (final v in fileVehicles ?? const <Vehicle>[])
        if (!deviceIds.contains(v.id)) v,
    ];
    logs = _ownedBy(logs, {...deviceIds, ...newVehicles.map((v) => v.id)});
    // Logs sent to the default vehicle need it to exist, even if the user
    // deleted it in favour of others. One transaction, so a failure adds
    // neither the vehicles nor the logs.
    await db.mergeData(newVehicles, logs,
        ensureDefault: logs.any((l) => l.vehicleId == kDefaultVehicleId));
  }

  return logs.length;
}

/// [logs] with any vehicle id outside [known] moved to the default vehicle,
/// so no restored log is left belonging to no vehicle.
List<FuelLog> _ownedBy(List<FuelLog> logs, Set<String> known) => [
      for (final l in logs)
        known.contains(l.vehicleId)
            ? l
            : l.copyWith(vehicleId: kDefaultVehicleId),
    ];
