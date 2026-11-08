import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../models/fuel_log.dart';
import '../models/pump.dart';
import '../models/service_record.dart';
import '../models/service_type.dart';
import '../models/vehicle.dart';
import '../models/workshop.dart';
import '../theme/palettes.dart';
import '../utils/appearance_prefs.dart';
import '../utils/constants.dart';
import '../utils/brand_grades.dart';
import '../utils/vehicle_manager.dart';
import 'service_reminders.dart';

/// Sentinel validated on restore so a foreign backup file is rejected.
const kBackupApp = 'fuelpulse';
// v2 added pumpBrands; v3 added vehicles and moved tank capacity onto them;
// v4 added pumps, workshops, service types, services and brand grades.
// Restore tolerates every older shape, and refuses a newer one.
const kBackupVersion = 4;

/// Snapshot everything worth backing up: every vehicle and all their logs
/// (including costs), the fuel type and pump brand lists, and the settings
/// prefs. Callers must await this BEFORE the first network await of an
/// upload, so a concurrent "Delete all data" can't land in the sign-in
/// window and get uploaded as the newest backup.
Future<Map<String, dynamic>> buildBackupPayload() async {
  final db = DatabaseHelper();
  final logs = await db.getEveryLogChrono();
  final vehicles = await db.getVehicles();
  final brandGrades = await loadBrandGrades();
  final pumps = await db.getPumps();
  final workshops = await db.getWorkshops();
  final serviceTypes = await db.getServiceTypes();
  final services = await db.getEveryService();
  final prefs = await SharedPreferences.getInstance();
  return {
    'app': kBackupApp,
    'version': kBackupVersion,
    'vehicles': vehicles.map((v) => v.toMap()).toList(),
    'logs': logs.map((l) => l.toMap()).toList(),
    'pumps': pumps.map((p) => p.toMap()).toList(),
    'workshops': workshops.map((w) => w.toMap()).toList(),
    'serviceTypes': serviceTypes.map((t) => t.toMap()).toList(),
    // typeIds as a list, not the JSON string SQLite keeps.
    'services': [
      for (final s in services) {...s.toMap(), 'typeIds': s.typeIds},
    ],
    // The two flat lists v2.x read; a format 4 file restores from the map.
    'brandGrades': brandGrades,
    'fuelTypes': allGrades(brandGrades),
    'pumpBrands': brandGrades.keys.toList(),
    'settings': {
      'activeVehicleId': prefs.getString(kActiveVehicleKey),
      // From v2.2.0. Older files carry themeAccent and themeLight instead,
      // which restore ignores: those colours have no palette.
      'paletteId': prefs.getString(kPaletteIdKey),
      'themeMode': prefs.getString(kThemeModeKey),
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

  // Null for a format 1 to 3 file.
  List<T>? list<T>(String key, T Function(Map<String, dynamic>) fromMap) {
    final raw = data[key];
    if (raw == null) return null;
    try {
      return [
        for (final m in raw as List) fromMap(Map<String, dynamic>.from(m as Map)),
      ];
    } catch (e) {
      throw FormatException('Backup contains a malformed $key entry: $e');
    }
  }

  final pumps = list('pumps', Pump.fromMap) ?? const <Pump>[];
  final workshops = list('workshops', Workshop.fromMap) ?? const <Workshop>[];
  final serviceTypes =
      list('serviceTypes', ServiceType.fromMap) ?? const <ServiceType>[];
  var services = list('services', ServiceRecord.fromMap) ?? const <ServiceRecord>[];

  final db = DatabaseHelper();
  final settings = data['settings'] is Map ? data['settings'] as Map : null;

  if (replace) {
    final vehicles = List.of(fileVehicles ?? const <Vehicle>[]);
    final ids = vehicles.map((v) => v.id).toSet();
    logs = _ownedBy(logs, ids.isEmpty ? {kDefaultVehicleId} : ids);
    services = _servicesOwnedBy(services, ids.isEmpty ? {kDefaultVehicleId} : ids);
    // The default vehicle is added when the file has no vehicles (v1/v2)
    // or some log was moved to it by [_ownedBy].
    final needsDefault = vehicles.isEmpty ||
        logs.any((l) => l.vehicleId == kDefaultVehicleId) ||
        services.any((s) => s.vehicleId == kDefaultVehicleId);
    if (needsDefault && !ids.contains(kDefaultVehicleId)) {
      vehicles.add(DatabaseHelper.defaultVehicle(sortOrder: vehicles.length));
    }
    await db.replaceAllData(vehicles, logs,
        pumps: pumps,
        workshops: workshops,
        serviceTypes: serviceTypes,
        services: services);

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
      final palette = settings['paletteId'];
      final mode = settings['themeMode'];
      if (palette is String || mode is String) {
        final now = await loadAppearance();
        await saveAppearance(now.copyWith(
          paletteId: palette is String ? paletteById(palette).id : null,
          mode: mode is String ? themeModeFromName(mode) : null,
        ));
      }
    } else {
      await prefs.remove(kActiveVehicleKey);
    }

    // A v3.0.0 file carries the map; an older one only its two lists,
    // which seed it the same way an upgrade does.
    final grades = data['brandGrades'];
    final types = data['fuelTypes'];
    final brands = data['pumpBrands'];
    if (grades is Map && grades.isNotEmpty) {
      await saveBrandGrades({
        for (final e in grades.entries)
          '${e.key}': (e.value as List).map((g) => '$g').toList(),
      });
    } else if (brands is List && brands.isNotEmpty ||
        types is List && types.isNotEmpty) {
      final current = await loadBrandGrades();
      await saveBrandGrades(seedBrandGrades(
        brands is List && brands.isNotEmpty
            ? brands.map((b) => '$b').toList()
            : current.keys.toList(),
        types is List && types.isNotEmpty
            ? types.map((t) => '$t').toList()
            : const [kDefaultFuelType],
      ));
    }
  } else {
    final deviceIds = (await db.getVehicles()).map((v) => v.id).toSet();
    final newVehicles = [
      for (final v in fileVehicles ?? const <Vehicle>[])
        if (!deviceIds.contains(v.id)) v,
    ];
    final known = {...deviceIds, ...newVehicles.map((v) => v.id)};
    logs = _ownedBy(logs, known);
    services = _servicesOwnedBy(services, known);
    // Logs sent to the default vehicle need it to exist, even if the user
    // deleted it in favour of others. One transaction, so a failure adds
    // neither the vehicles nor the logs.
    await db.mergeData(newVehicles, logs,
        ensureDefault: logs.any((l) => l.vehicleId == kDefaultVehicleId) ||
            services.any((s) => s.vehicleId == kDefaultVehicleId),
        pumps: pumps,
        workshops: workshops,
        serviceTypes: serviceTypes,
        services: services);
  }

  await ServiceReminders.instance.rescheduleAll();
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

/// [services] with any vehicle id outside [known] moved to the default
/// vehicle, as [_ownedBy] does for logs.
List<ServiceRecord> _servicesOwnedBy(
        List<ServiceRecord> services, Set<String> known) =>
    [
      for (final s in services)
        known.contains(s.vehicleId)
            ? s
            : ServiceRecord.fromMap(
                {...s.toMap(), 'vehicleId': kDefaultVehicleId}),
    ];
