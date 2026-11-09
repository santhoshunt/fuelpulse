import 'dart:io' show File;

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/attachment.dart';
import '../models/check.dart';
import '../models/fuel_log.dart';
import '../models/paper.dart';
import '../models/part.dart';
import '../models/pump.dart';
import '../models/service_record.dart';
import '../models/service_type.dart';
import '../models/trip.dart';
import '../models/vehicle.dart';
import '../models/workshop.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static const int schemaVersion = 7;

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'fuelpulse.db');
    await _copyBeforeV4(path);
    return await openDatabase(
      path,
      version: schemaVersion,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
    );
  }

  /// A second safety net beside the migration's transaction: before a
  /// schema 3 database first opens as schema 4, keep a copy of it as
  /// fuelpulse_pre_v4.db in the same folder.
  static Future<void> _copyBeforeV4(String path) async {
    try {
      final file = File(path);
      final copy = File(join(dirname(path), 'fuelpulse_pre_v4.db'));
      if (!await file.exists() || await copy.exists()) return;
      final old = await openReadOnlyDatabase(path);
      final version = await old.getVersion();
      await old.close();
      if (version < 4) await file.copy(copy.path);
    } catch (e) {
      debugPrint('Pre-v4 copy failed: $e');
    }
  }

  /// A fresh install builds schema 3 and then runs the same schema 4 step
  /// as an upgrade, so there is one path to get right.
  @visibleForTesting
  static Future<void> onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE fuel_logs (
        id TEXT PRIMARY KEY,
        timestamp TEXT NOT NULL,
        odometer INTEGER NOT NULL,
        liters REAL NOT NULL,
        pumpBrand TEXT NOT NULL DEFAULT '',
        fullTank INTEGER NOT NULL DEFAULT 1,
        notes TEXT NOT NULL DEFAULT '',
        fuelType TEXT NOT NULL DEFAULT 'Normal',
        totalCost REAL,
        pricePerLitre REAL,
        vehicleId TEXT NOT NULL DEFAULT '$kDefaultVehicleId'
      )
    ''');
    await _createVehicles(db);
    await db.execute(_createVehicleIndex);
    await _toV4(db);
    await _toV5(db);
    await _toV6(db);
    await _toV7(db);
  }

  @visibleForTesting
  static Future<void> onUpgrade(
      Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          "ALTER TABLE fuel_logs ADD COLUMN fuelType TEXT NOT NULL DEFAULT 'Normal'");
      await db.execute('ALTER TABLE fuel_logs ADD COLUMN totalCost REAL');
      await db.execute('ALTER TABLE fuel_logs ADD COLUMN pricePerLitre REAL');
    }
    if (oldVersion < 3) {
      // Every existing log belongs to the one vehicle the app tracked
      // before; the column default puts them there without a rewrite.
      await _createVehicles(db);
      await db.execute(
          "ALTER TABLE fuel_logs ADD COLUMN vehicleId TEXT NOT NULL DEFAULT '$kDefaultVehicleId'");
      await db.execute(_createVehicleIndex);
    }
    if (oldVersion < 4) await _toV4(db);
    if (oldVersion < 5) await _toV5(db);
    if (oldVersion < 6) await _toV6(db);
    if (oldVersion < 7) await _toV7(db);
  }

  /// Schema 7, additive only: repeating checks you do yourself.
  static Future<void> _toV7(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE checks (
        id TEXT PRIMARY KEY,
        vehicleId TEXT NOT NULL,
        name TEXT NOT NULL,
        everyDays INTEGER,
        everyKm INTEGER,
        lastDoneAt TEXT NOT NULL,
        lastDoneKm INTEGER NOT NULL DEFAULT 0
      )
    ''');
  }

  /// Schema 6, additive only: trips, papers, parts and attachments (bills
  /// and document photos); a trip id on each log; a monthly fuel budget on
  /// each vehicle.
  static Future<void> _toV6(DatabaseExecutor db) async {
    await db.execute('ALTER TABLE fuel_logs ADD COLUMN tripId TEXT');
    await db.execute('ALTER TABLE vehicles ADD COLUMN monthlyBudget REAL');
    await db.execute('''
      CREATE TABLE trips (
        id TEXT PRIMARY KEY,
        vehicleId TEXT NOT NULL,
        name TEXT NOT NULL,
        startAt TEXT NOT NULL,
        startOdometer INTEGER NOT NULL,
        endAt TEXT,
        endOdometer INTEGER,
        notes TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_trips_vehicle ON trips(vehicleId, startAt)');
    await db.execute('''
      CREATE TABLE papers (
        id TEXT PRIMARY KEY,
        vehicleId TEXT NOT NULL,
        kind TEXT NOT NULL,
        title TEXT NOT NULL DEFAULT '',
        number TEXT NOT NULL DEFAULT '',
        issuedOn TEXT,
        expiresOn TEXT,
        remindDays INTEGER NOT NULL DEFAULT 7,
        notes TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE parts (
        id TEXT PRIMARY KEY,
        vehicleId TEXT NOT NULL,
        kind TEXT NOT NULL,
        label TEXT NOT NULL,
        brand TEXT NOT NULL DEFAULT '',
        fittedAt TEXT NOT NULL,
        fittedOdometer INTEGER NOT NULL,
        lifeKm INTEGER,
        lifeMonths INTEGER,
        warrantyUntil TEXT,
        notes TEXT NOT NULL DEFAULT ''
      )
    ''');
    await db.execute('''
      CREATE TABLE attachments (
        id TEXT PRIMARY KEY,
        ownerType TEXT NOT NULL,
        ownerId TEXT NOT NULL,
        file TEXT NOT NULL,
        kind TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_attachments_owner ON attachments(ownerType, ownerId)');
  }

  /// Schema 5: per-vehicle cost per km bands and picture choice.
  static Future<void> _toV5(DatabaseExecutor db) async {
    await db.execute('ALTER TABLE vehicles ADD COLUMN costBands TEXT');
    await db.execute('ALTER TABLE vehicles ADD COLUMN icon TEXT');
  }

  /// Schema 4, additive only: pumps as named stations of a brand,
  /// workshops, service types and service records; a pump id on each log;
  /// make and model and mileage bands on each vehicle. Every existing brand
  /// becomes one pump so old logs point at a pump straight away.
  static Future<void> _toV4(DatabaseExecutor db) async {
    await db.execute('ALTER TABLE fuel_logs ADD COLUMN pumpId TEXT');
    await db.execute(
        "ALTER TABLE vehicles ADD COLUMN model TEXT NOT NULL DEFAULT ''");
    await db.execute('ALTER TABLE vehicles ADD COLUMN mileageBands TEXT');
    await db.execute('''
      CREATE TABLE pumps (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        brand TEXT NOT NULL,
        isFavourite INTEGER NOT NULL DEFAULT 0,
        sortOrder INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE workshops (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        area TEXT NOT NULL DEFAULT '',
        phone TEXT NOT NULL DEFAULT '',
        sortOrder INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE service_types (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        intervalKm INTEGER,
        intervalMonths INTEGER,
        sortOrder INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE services (
        id TEXT PRIMARY KEY,
        vehicleId TEXT NOT NULL,
        timestamp TEXT NOT NULL,
        odometer INTEGER NOT NULL,
        workshopId TEXT,
        typeIds TEXT NOT NULL DEFAULT '[]',
        cost REAL,
        notes TEXT NOT NULL DEFAULT '',
        nextDueKm INTEGER,
        nextDueDate TEXT
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_services_vehicle ON services(vehicleId, timestamp)');
    await _seedServiceTypes(db);
    await linkLogsToPumps(db);
  }

  static Future<void> _seedServiceTypes(DatabaseExecutor db) async {
    for (final t in ServiceType.defaults) {
      await db.insert('service_types', t.toMap(),
          conflictAlgorithm: ConflictAlgorithm.ignore);
    }
  }

  /// Points every log without a pump at a pump of its brand: one with no
  /// station name, created when missing. Brands are matched ignoring case;
  /// the first spelling met names the pump. Used by the schema 4 migration
  /// and after restoring or importing logs from before pumps existed.
  @visibleForTesting
  static Future<void> linkLogsToPumps(DatabaseExecutor db) async {
    final rows = await db.rawQuery("SELECT DISTINCT pumpBrand FROM fuel_logs "
        "WHERE pumpId IS NULL AND pumpBrand != '' ORDER BY rowid");
    final pumps = (await db.query('pumps')).map(Pump.fromMap).toList();
    final byBrand = <String, String>{
      for (final p in pumps.reversed)
        if (p.name.isEmpty) p.brand.toLowerCase(): p.id,
    };
    for (final r in rows) {
      final brand = r['pumpBrand'] as String;
      final key = brand.toLowerCase();
      var id = byBrand[key];
      if (id == null) {
        // The index keeps ids made in the same millisecond apart.
        id = '${Pump.generateId()}${byBrand.length}';
        await db.insert(
            'pumps',
            Pump(
              id: id,
              name: '',
              brand: brand,
              sortOrder: byBrand.length,
              createdAt: DateTime.now().toIso8601String(),
            ).toMap());
        byBrand[key] = id;
      }
      await db.rawUpdate(
          'UPDATE fuel_logs SET pumpId = ? '
          'WHERE pumpId IS NULL AND lower(pumpBrand) = ?',
          [id, key]);
    }
  }

  static const _createVehicleIndex =
      'CREATE INDEX idx_fuel_logs_vehicle ON fuel_logs(vehicleId, timestamp)';

  /// The vehicles table plus the default vehicle (schema 3).
  static Future<void> _createVehicles(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE vehicles (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL DEFAULT 'car',
        tankCapacity REAL,
        sortOrder INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL
      )
    ''');
    // Schema 3 columns only: model and mileageBands arrive with schema 4.
    await db.insert('vehicles',
        defaultVehicle().toMap()
          ..remove('model')
          ..remove('mileageBands')
          ..remove('costBands')
          ..remove('icon')
          ..remove('monthlyBudget'));
  }

  /// The vehicle every pre-v2.0.0 log belongs to, as created by the schema 3
  /// migration, a fresh install, a wipe, or a restore that needs it.
  static Vehicle defaultVehicle({int sortOrder = 0}) => Vehicle(
        id: kDefaultVehicleId,
        name: kDefaultVehicleName,
        sortOrder: sortOrder,
        createdAt: DateTime.now().toIso8601String(),
      );

  // ── Logs ──────────────────────────────────────────────────────────────

  /// Insert a new fuel log entry.
  /// A log saved with a brand but no pump gets the brand's pump.
  Future<void> insertLog(FuelLog log) async {
    final db = await database;
    await db.insert('fuel_logs', log.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
    if (log.pumpId == null) await linkLogsToPumps(db);
  }

  /// Update an existing fuel log entry.
  Future<void> updateLog(FuelLog log) async {
    final db = await database;
    await db.update(
      'fuel_logs',
      log.toMap(),
      where: 'id = ?',
      whereArgs: [log.id],
    );
    if (log.pumpId == null) await linkLogsToPumps(db);
  }

  /// Delete a fuel log entry by ID, with its receipts. Returns the
  /// receipts' file names for the caller to delete.
  Future<List<String>> deleteLog(String id) async {
    final db = await database;
    return db.transaction((txn) async {
      await txn.delete('fuel_logs', where: 'id = ?', whereArgs: [id]);
      return _dropAttachments(txn, 'fuel', id);
    });
  }

  /// One vehicle's logs, newest-first (for display).
  Future<List<FuelLog>> getAllLogs(String vehicleId) async {
    final db = await database;
    final maps = await db.query('fuel_logs',
        where: 'vehicleId = ?',
        whereArgs: [vehicleId],
        orderBy: 'timestamp DESC');
    return maps.map((m) => FuelLog.fromMap(m)).toList();
  }

  /// One vehicle's logs, oldest-first (for calculations).
  Future<List<FuelLog>> getAllLogsChrono(String vehicleId) async {
    final db = await database;
    final maps = await db.query('fuel_logs',
        where: 'vehicleId = ?',
        whereArgs: [vehicleId],
        orderBy: 'timestamp ASC');
    return maps.map((m) => FuelLog.fromMap(m)).toList();
  }

  /// Every vehicle's logs, oldest-first. Backups only: anything that
  /// calculates or displays must use [getAllLogsChrono].
  Future<List<FuelLog>> getEveryLogChrono() async {
    final db = await database;
    final maps = await db.query('fuel_logs', orderBy: 'timestamp ASC');
    return maps.map((m) => FuelLog.fromMap(m)).toList();
  }

  /// Get a single log by ID.
  Future<FuelLog?> getLogById(String id) async {
    final db = await database;
    final maps =
        await db.query('fuel_logs', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return FuelLog.fromMap(maps.first);
  }

  /// Count of every vehicle's logs (backup guards, restore dialogs).
  Future<int> getLogCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM fuel_logs');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Count of one vehicle's logs.
  Future<int> getLogCountFor(String vehicleId) async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as cnt FROM fuel_logs WHERE vehicleId = ?',
        [vehicleId]);
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// One vehicle's most recent log entry (by timestamp).
  Future<FuelLog?> getLastLog(String vehicleId) async {
    final db = await database;
    final maps = await db.query('fuel_logs',
        where: 'vehicleId = ?',
        whereArgs: [vehicleId],
        orderBy: 'timestamp DESC',
        limit: 1);
    if (maps.isEmpty) return null;
    return FuelLog.fromMap(maps.first);
  }

  /// The newest fill-up at [pumpId] that has a price or a total, from any
  /// vehicle: a pump's rate is the same whatever you fill.
  Future<FuelLog?> lastPricedLogAt(String pumpId) async {
    final db = await database;
    final maps = await db.query('fuel_logs',
        where: 'pumpId = ? AND (pricePerLitre IS NOT NULL OR totalCost IS NOT NULL)',
        whereArgs: [pumpId],
        orderBy: 'timestamp DESC',
        limit: 1);
    return maps.isEmpty ? null : FuelLog.fromMap(maps.first);
  }

  /// Delete all log entries.
  Future<void> deleteAllLogs() async {
    final db = await database;
    await db.delete('fuel_logs');
  }

  /// Rename a pump brand on every log and pump referencing it.
  /// Returns the number of updated logs.
  Future<int> renamePumpBrand(String from, String to) async {
    final db = await database;
    return db.transaction((txn) async {
      await txn.update('pumps', {'brand': to},
          where: 'brand = ?', whereArgs: [from]);
      return txn.update(
        'fuel_logs',
        {'pumpBrand': to},
        where: 'pumpBrand = ?',
        whereArgs: [from],
      );
    });
  }

  /// Rename one brand's fuel grade on that brand's logs.
  /// Returns the number of updated rows.
  Future<int> renameGrade(String brand, String from, String to) async {
    final db = await database;
    return db.update(
      'fuel_logs',
      {'fuelType': to},
      where: 'pumpBrand = ? AND fuelType = ?',
      whereArgs: [brand, from],
    );
  }

  /// Insert multiple logs (for CSV import).
  Future<void> insertLogs(List<FuelLog> logs) async {
    final db = await database;
    final batch = db.batch();
    for (final log in logs) {
      batch.insert('fuel_logs', log.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    // CSV rows carry a brand, not a pump.
    await linkLogsToPumps(db);
  }

  // ── Vehicles ──────────────────────────────────────────────────────────

  Future<List<Vehicle>> getVehicles() async {
    final db = await database;
    final maps = await db.query('vehicles', orderBy: 'sortOrder, createdAt');
    return maps.map((m) => Vehicle.fromMap(m)).toList();
  }

  Future<Vehicle?> getVehicle(String id) async {
    final db = await database;
    final maps =
        await db.query('vehicles', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Vehicle.fromMap(maps.first);
  }

  Future<void> insertVehicle(Vehicle v) async {
    final db = await database;
    await db.insert('vehicles', v.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateVehicle(Vehicle v) async {
    final db = await database;
    await db.update('vehicles', v.toMap(), where: 'id = ?', whereArgs: [v.id]);
  }

  /// Removes the vehicle and everything it owns, together or not at all.
  /// Returns the file names of the bills and photos it owned, for the
  /// caller to delete.
  Future<List<String>> deleteVehicle(String id) async {
    final db = await database;
    return db.transaction((txn) async {
      const owned = "(ownerType = 'service' AND ownerId IN "
          '(SELECT id FROM services WHERE vehicleId = ?)) OR '
          "(ownerType = 'fuel' AND ownerId IN "
          '(SELECT id FROM fuel_logs WHERE vehicleId = ?)) OR '
          "(ownerType = 'paper' AND ownerId IN "
          '(SELECT id FROM papers WHERE vehicleId = ?))';
      final files = [
        for (final r in await txn.query('attachments',
            columns: ['file'], where: owned, whereArgs: [id, id, id]))
          r['file'] as String,
      ];
      await txn.delete('attachments', where: owned, whereArgs: [id, id, id]);
      for (final table in const [
        'fuel_logs',
        'services',
        'trips',
        'papers',
        'parts',
        'checks',
      ]) {
        await txn.delete(table, where: 'vehicleId = ?', whereArgs: [id]);
      }
      await txn.delete('vehicles', where: 'id = ?', whereArgs: [id]);
      return files;
    });
  }

  /// Re-creates the default vehicle when the user deleted it, so logs
  /// assigned to it (old backups, unknown ids) always have an owner.
  Future<void> ensureDefaultVehicle() async {
    if (await getVehicle(kDefaultVehicleId) != null) return;
    await insertVehicle(defaultVehicle());
  }

  /// Delete-all: no logs, pumps, workshops or services, the default
  /// service types, and only the default vehicle.
  Future<void> resetToDefaultVehicle() async {
    final db = await database;
    await db.transaction((txn) async {
      await _clearAll(txn);
      await txn.insert('vehicles', defaultVehicle().toMap());
      await _seedServiceTypes(txn);
    });
  }

  static Future<void> _clearAll(DatabaseExecutor txn) async {
    for (final table in const [
      'fuel_logs',
      'vehicles',
      'pumps',
      'workshops',
      'service_types',
      'services',
      'trips',
      'papers',
      'parts',
      'attachments',
      'checks',
    ]) {
      await txn.delete(table);
    }
  }

  /// Merge-mode restore: adds [newVehicles] (ids not on the device) and
  /// upserts [logs] by id, in one transaction so a failure part-way adds
  /// nothing. With [ensureDefault], re-creates the default vehicle first if
  /// it was deleted, for logs the caller assigned to it.
  /// Pumps, workshops and service types the device already has (by id)
  /// win; services are upserted like logs.
  Future<void> mergeData(
    List<Vehicle> newVehicles,
    List<FuelLog> logs, {
    bool ensureDefault = false,
    List<Pump> pumps = const [],
    List<Workshop> workshops = const [],
    List<ServiceType> serviceTypes = const [],
    List<ServiceRecord> services = const [],
    List<Trip> trips = const [],
    List<Paper> papers = const [],
    List<Part> parts = const [],
    List<Attachment> attachments = const [],
    List<Check> checks = const [],
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await _insertAll(txn, trips, papers, parts, attachments,
          ConflictAlgorithm.replace);
      for (final c in checks) {
        await txn.insert('checks', c.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final v in newVehicles) {
        await txn.insert('vehicles', v.toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      // After the file's own vehicles, so a default vehicle the file
      // carries (renamed, with a tank size) wins over the generic one,
      // which only fills the gap.
      if (ensureDefault) {
        await txn.insert('vehicles', defaultVehicle().toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (final p in pumps) {
        await txn.insert('pumps', {...p.toMap(), 'isFavourite': 0},
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (final w in workshops) {
        await txn.insert('workshops', w.toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (final t in serviceTypes) {
        await txn.insert('service_types', t.toMap(),
            conflictAlgorithm: ConflictAlgorithm.ignore);
      }
      for (final s in services) {
        await txn.insert('services', s.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final log in logs) {
        await txn.insert('fuel_logs', log.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await linkLogsToPumps(txn);
    });
  }

  /// Replace-mode restore: swaps everything in one transaction, so a
  /// failure part-way leaves the old data in place. An empty [vehicles]
  /// list falls back to the default vehicle and an empty [serviceTypes]
  /// list to the default types; logs without a pump get one per brand.
  Future<void> replaceAllData(
    List<Vehicle> vehicles,
    List<FuelLog> logs, {
    List<Pump> pumps = const [],
    List<Workshop> workshops = const [],
    List<ServiceType> serviceTypes = const [],
    List<ServiceRecord> services = const [],
    List<Trip> trips = const [],
    List<Paper> papers = const [],
    List<Part> parts = const [],
    List<Attachment> attachments = const [],
    List<Check> checks = const [],
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      await _clearAll(txn);
      await _insertAll(txn, trips, papers, parts, attachments,
          ConflictAlgorithm.replace);
      for (final c in checks) {
        await txn.insert('checks', c.toMap());
      }
      for (final p in pumps) {
        await txn.insert('pumps', p.toMap());
      }
      for (final w in workshops) {
        await txn.insert('workshops', w.toMap());
      }
      if (serviceTypes.isEmpty) {
        await _seedServiceTypes(txn);
      } else {
        for (final s in serviceTypes) {
          await txn.insert('service_types', s.toMap());
        }
      }
      for (final s in services) {
        await txn.insert('services', s.toMap());
      }
      for (final v in vehicles.isEmpty ? [defaultVehicle()] : vehicles) {
        await txn.insert('vehicles', v.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final log in logs) {
        await txn.insert('fuel_logs', log.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await linkLogsToPumps(txn);
    });
  }

  // ── Pumps ─────────────────────────────────────────────────────────────

  /// Favourite first, then in the order they were added.
  Future<List<Pump>> getPumps() async {
    final db = await database;
    final maps = await db.query('pumps',
        orderBy: 'isFavourite DESC, sortOrder, createdAt');
    return maps.map(Pump.fromMap).toList();
  }

  /// Adds or replaces [p]. A favourite pump unmarks every other one: the
  /// form pre-selects the one favourite.
  Future<void> savePump(Pump p) async {
    final db = await database;
    await db.transaction((txn) async {
      if (p.isFavourite) await txn.update('pumps', {'isFavourite': 0});
      await txn.insert('pumps', p.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  /// How many fill-ups each pump has, by pump id.
  Future<Map<String, int>> pumpUseCounts() async {
    final db = await database;
    final rows = await db.rawQuery(
        'SELECT pumpId, COUNT(*) AS n FROM fuel_logs '
        'WHERE pumpId IS NOT NULL GROUP BY pumpId');
    return {for (final r in rows) r['pumpId'] as String: r['n'] as int};
  }

  /// Logs keep their pump id and brand, so they still show the brand.
  Future<void> deletePump(String id) async {
    final db = await database;
    await db.delete('pumps', where: 'id = ?', whereArgs: [id]);
  }

  // ── Workshops ─────────────────────────────────────────────────────────

  Future<List<Workshop>> getWorkshops() async {
    final db = await database;
    final maps = await db.query('workshops', orderBy: 'sortOrder, name');
    return maps.map(Workshop.fromMap).toList();
  }

  Future<void> upsertWorkshop(Workshop w) async {
    final db = await database;
    await db.insert('workshops', w.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteWorkshop(String id) async {
    final db = await database;
    await db.delete('workshops', where: 'id = ?', whereArgs: [id]);
  }

  // ── Service types ─────────────────────────────────────────────────────

  Future<List<ServiceType>> getServiceTypes() async {
    final db = await database;
    final maps = await db.query('service_types', orderBy: 'sortOrder, name');
    return maps.map(ServiceType.fromMap).toList();
  }

  Future<void> upsertServiceType(ServiceType t) async {
    final db = await database;
    await db.insert('service_types', t.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteServiceType(String id) async {
    final db = await database;
    await db.delete('service_types', where: 'id = ?', whereArgs: [id]);
  }

  // ── Services ──────────────────────────────────────────────────────────

  /// One vehicle's services, newest first.
  Future<List<ServiceRecord>> getServices(String vehicleId) async {
    final db = await database;
    final maps = await db.query('services',
        where: 'vehicleId = ?',
        whereArgs: [vehicleId],
        orderBy: 'timestamp DESC');
    return maps.map(ServiceRecord.fromMap).toList();
  }

  /// Every vehicle's services, oldest first. Backups only.
  Future<List<ServiceRecord>> getEveryService() async {
    final db = await database;
    final maps = await db.query('services', orderBy: 'timestamp ASC');
    return maps.map(ServiceRecord.fromMap).toList();
  }

  Future<void> insertService(ServiceRecord s) async {
    final db = await database;
    await db.insert('services', s.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> updateService(ServiceRecord s) async {
    final db = await database;
    await db.update('services', s.toMap(), where: 'id = ?', whereArgs: [s.id]);
  }

  /// Deletes the service with its bills. Returns the bills' file names for
  /// the caller to delete.
  Future<List<String>> deleteService(String id) async {
    final db = await database;
    return db.transaction((txn) async {
      await txn.delete('services', where: 'id = ?', whereArgs: [id]);
      return _dropAttachments(txn, 'service', id);
    });
  }

  // ── Schema 6 tables ───────────────────────────────────────────────────

  static Future<void> _insertAll(
    DatabaseExecutor txn,
    List<Trip> trips,
    List<Paper> papers,
    List<Part> parts,
    List<Attachment> attachments,
    ConflictAlgorithm onConflict,
  ) async {
    for (final t in trips) {
      await txn.insert('trips', t.toMap(), conflictAlgorithm: onConflict);
    }
    for (final p in papers) {
      await txn.insert('papers', p.toMap(), conflictAlgorithm: onConflict);
    }
    for (final p in parts) {
      await txn.insert('parts', p.toMap(), conflictAlgorithm: onConflict);
    }
    for (final a in attachments) {
      await txn.insert('attachments', a.toMap(), conflictAlgorithm: onConflict);
    }
  }

  /// Deletes an owner's attachment rows and returns their file names.
  static Future<List<String>> _dropAttachments(
      DatabaseExecutor txn, String ownerType, String ownerId) async {
    const where = 'ownerType = ? AND ownerId = ?';
    final rows = await txn.query('attachments',
        columns: ['file'], where: where, whereArgs: [ownerType, ownerId]);
    await txn.delete('attachments', where: where, whereArgs: [ownerType, ownerId]);
    return [for (final r in rows) r['file'] as String];
  }

  // Trips

  /// One vehicle's trips, newest first.
  Future<List<Trip>> getTrips(String vehicleId) async {
    final db = await database;
    final maps = await db.query('trips',
        where: 'vehicleId = ?', whereArgs: [vehicleId], orderBy: 'startAt DESC');
    return maps.map(Trip.fromMap).toList();
  }

  Future<List<Trip>> getEveryTrip() async {
    final db = await database;
    return (await db.query('trips', orderBy: 'startAt ASC'))
        .map(Trip.fromMap)
        .toList();
  }

  Future<Trip?> getTrip(String id) async {
    final db = await database;
    final maps = await db.query('trips', where: 'id = ?', whereArgs: [id]);
    return maps.isEmpty ? null : Trip.fromMap(maps.first);
  }

  /// The trip on [vehicleId] that has not ended, or null.
  Future<Trip?> activeTrip(String vehicleId) async {
    final db = await database;
    final maps = await db.query('trips',
        where: 'vehicleId = ? AND endAt IS NULL',
        whereArgs: [vehicleId],
        orderBy: 'startAt DESC',
        limit: 1);
    return maps.isEmpty ? null : Trip.fromMap(maps.first);
  }

  Future<void> saveTrip(Trip t) async {
    final db = await database;
    await db.insert('trips', t.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Deletes the trip; its fill-ups stay, no longer on a trip.
  Future<void> deleteTrip(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update('fuel_logs', {'tripId': null},
          where: 'tripId = ?', whereArgs: [id]);
      await txn.delete('trips', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Takes fill-ups made after [endAt] off the trip.
  Future<void> untagAfter(String tripId, String endAt) async {
    final db = await database;
    await db.update('fuel_logs', {'tripId': null},
        where: 'tripId = ? AND timestamp > ?', whereArgs: [tripId, endAt]);
  }

  /// A trip's fill-ups, oldest first.
  Future<List<FuelLog>> getTripLogs(String tripId) async {
    final db = await database;
    final maps = await db.query('fuel_logs',
        where: 'tripId = ?', whereArgs: [tripId], orderBy: 'timestamp ASC');
    return maps.map(FuelLog.fromMap).toList();
  }

  // Papers

  /// One vehicle's papers, the nearest expiry first, then those without one.
  Future<List<Paper>> getPapers(String vehicleId) async {
    final db = await database;
    final maps = await db.query('papers',
        where: 'vehicleId = ?',
        whereArgs: [vehicleId],
        orderBy: 'expiresOn IS NULL, expiresOn, kind');
    return maps.map(Paper.fromMap).toList();
  }

  Future<List<Paper>> getEveryPaper() async {
    final db = await database;
    return (await db.query('papers')).map(Paper.fromMap).toList();
  }

  Future<void> savePaper(Paper p) async {
    final db = await database;
    await db.insert('papers', p.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Deletes the paper with its photos. Returns the photos' file names for
  /// the caller to delete.
  Future<List<String>> deletePaper(String id) async {
    final db = await database;
    return db.transaction((txn) async {
      await txn.delete('papers', where: 'id = ?', whereArgs: [id]);
      return _dropAttachments(txn, 'paper', id);
    });
  }

  // Parts

  Future<List<Part>> getParts(String vehicleId) async {
    final db = await database;
    final maps = await db.query('parts',
        where: 'vehicleId = ?', whereArgs: [vehicleId], orderBy: 'kind, label');
    return maps.map(Part.fromMap).toList();
  }

  Future<List<Part>> getEveryPart() async {
    final db = await database;
    return (await db.query('parts')).map(Part.fromMap).toList();
  }

  Future<void> savePart(Part p) async {
    final db = await database;
    await db.insert('parts', p.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deletePart(String id) async {
    final db = await database;
    await db.delete('parts', where: 'id = ?', whereArgs: [id]);
  }

  // Checks

  Future<List<Check>> getChecks(String vehicleId) async {
    final db = await database;
    final maps = await db.query('checks',
        where: 'vehicleId = ?', whereArgs: [vehicleId], orderBy: 'name');
    return maps.map(Check.fromMap).toList();
  }

  Future<List<Check>> getEveryCheck() async {
    final db = await database;
    return (await db.query('checks')).map(Check.fromMap).toList();
  }

  Future<void> saveCheck(Check c) async {
    final db = await database;
    await db.insert('checks', c.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> deleteCheck(String id) async {
    final db = await database;
    await db.delete('checks', where: 'id = ?', whereArgs: [id]);
  }

  // Attachments

  /// One owner's attachments, oldest first.
  Future<List<Attachment>> getAttachments(
      String ownerType, String ownerId) async {
    final db = await database;
    final maps = await db.query('attachments',
        where: 'ownerType = ? AND ownerId = ?',
        whereArgs: [ownerType, ownerId],
        orderBy: 'createdAt');
    return maps.map(Attachment.fromMap).toList();
  }

  /// How many attachments each owner of [ownerType] has, by owner id.
  Future<Map<String, int>> attachmentCounts(String ownerType) async {
    final db = await database;
    final rows = await db.rawQuery(
        'SELECT ownerId, COUNT(*) AS n FROM attachments '
        'WHERE ownerType = ? GROUP BY ownerId',
        [ownerType]);
    return {for (final r in rows) r['ownerId'] as String: r['n'] as int};
  }

  Future<List<Attachment>> getEveryAttachment() async {
    final db = await database;
    return (await db.query('attachments')).map(Attachment.fromMap).toList();
  }

  Future<void> saveAttachment(Attachment a) async {
    final db = await database;
    await db.insert('attachments', a.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Deletes one attachment row by id.
  Future<void> deleteAttachment(String id) async {
    final db = await database;
    await db.delete('attachments', where: 'id = ?', whereArgs: [id]);
  }
}
