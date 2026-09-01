import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/fuel_log.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._internal();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._internal();

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
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
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
        pricePerLitre REAL
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute(
          "ALTER TABLE fuel_logs ADD COLUMN fuelType TEXT NOT NULL DEFAULT 'Normal'");
      await db.execute('ALTER TABLE fuel_logs ADD COLUMN totalCost REAL');
      await db.execute('ALTER TABLE fuel_logs ADD COLUMN pricePerLitre REAL');
    }
  }

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

  /// Get all logs sorted newest-first (for display).
  Future<List<FuelLog>> getAllLogs() async {
    final db = await database;
    final maps = await db.query('fuel_logs', orderBy: 'timestamp DESC');
    return maps.map((m) => FuelLog.fromMap(m)).toList();
  }

  /// Get all logs sorted chronologically oldest-first (for calculations).
  Future<List<FuelLog>> getAllLogsChrono() async {
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

  /// Get the count of all log entries.
  Future<int> getLogCount() async {
    final db = await database;
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM fuel_logs');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Get the most recent log entry (by timestamp).
  Future<FuelLog?> getLastLog() async {
    final db = await database;
    final maps = await db.query('fuel_logs',
        orderBy: 'timestamp DESC', limit: 1);
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
}
