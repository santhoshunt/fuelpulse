import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/fuel_log.dart';
import '../models/vehicle.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

  static const int schemaVersion = 3;

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDb();
    return _database!;
  }

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'fuelpulse.db');
    return await openDatabase(
      path,
      version: schemaVersion,
      onCreate: onCreate,
      onUpgrade: onUpgrade,
    );
  }

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
    await db.insert('vehicles', defaultVehicle().toMap());
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
  Future<void> insertLog(FuelLog log) async {
    final db = await database;
    await db.insert('fuel_logs', log.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
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
  }

  /// Delete a fuel log entry by ID.
  Future<void> deleteLog(String id) async {
    final db = await database;
    await db.delete('fuel_logs', where: 'id = ?', whereArgs: [id]);
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

  /// Delete all log entries.
  Future<void> deleteAllLogs() async {
    final db = await database;
    await db.delete('fuel_logs');
  }

  /// Rename a fuel type on every log referencing it.
  /// Returns the number of updated rows.
  Future<int> renameFuelType(String from, String to) async {
    final db = await database;
    return db.update(
      'fuel_logs',
      {'fuelType': to},
      where: 'fuelType = ?',
      whereArgs: [from],
    );
  }

  /// Rename a pump brand on every log referencing it.
  /// Returns the number of updated rows.
  Future<int> renamePumpBrand(String from, String to) async {
    final db = await database;
    return db.update(
      'fuel_logs',
      {'pumpBrand': to},
      where: 'pumpBrand = ?',
      whereArgs: [from],
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

  /// Removes the vehicle and every log it owns, together or not at all.
  Future<void> deleteVehicle(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('fuel_logs', where: 'vehicleId = ?', whereArgs: [id]);
      await txn.delete('vehicles', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Re-creates the default vehicle when the user deleted it, so logs
  /// assigned to it (old backups, unknown ids) always have an owner.
  Future<void> ensureDefaultVehicle() async {
    if (await getVehicle(kDefaultVehicleId) != null) return;
    await insertVehicle(defaultVehicle());
  }

  /// Delete-all: no logs, and only the default vehicle.
  Future<void> resetToDefaultVehicle() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('fuel_logs');
      await txn.delete('vehicles');
      await txn.insert('vehicles', defaultVehicle().toMap());
    });
  }

  /// Merge-mode restore: adds [newVehicles] (ids not on the device) and
  /// upserts [logs] by id, in one transaction so a failure part-way adds
  /// nothing. With [ensureDefault], re-creates the default vehicle first if
  /// it was deleted, for logs the caller assigned to it.
  Future<void> mergeData(List<Vehicle> newVehicles, List<FuelLog> logs,
      {bool ensureDefault = false}) async {
    final db = await database;
    await db.transaction((txn) async {
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
      for (final log in logs) {
        await txn.insert('fuel_logs', log.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  /// Replace-mode restore: swaps every vehicle and log in one transaction,
  /// so a failure part-way leaves the old data in place. An empty
  /// [vehicles] list falls back to the default vehicle.
  Future<void> replaceAllData(List<Vehicle> vehicles, List<FuelLog> logs) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('fuel_logs');
      await txn.delete('vehicles');
      for (final v in vehicles.isEmpty ? [defaultVehicle()] : vehicles) {
        await txn.insert('vehicles', v.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final log in logs) {
        await txn.insert('fuel_logs', log.toMap(),
            conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }
}
