import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' show join;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fuelpulse/db/database_helper.dart';
import 'package:fuelpulse/models/fuel_log.dart';

// Schema version 1, as shipped in the first release. Frozen history: this is
// what real v1 installs have on disk, so it must never track onCreate.
const _v1CreateTable = '''
  CREATE TABLE fuel_logs (
    id TEXT PRIMARY KEY,
    timestamp TEXT NOT NULL,
    odometer INTEGER NOT NULL,
    liters REAL NOT NULL,
    pumpBrand TEXT NOT NULL DEFAULT '',
    fullTank INTEGER NOT NULL DEFAULT 1,
    notes TEXT NOT NULL DEFAULT ''
  )
''';

/// Column descriptions from PRAGMA table_info, as comparable strings.
Future<Set<String>> _columns(Database db) async {
  final rows = await db.rawQuery('PRAGMA table_info(fuel_logs)');
  return rows
      .map((r) => '${r['name']}|${r['type']}|${r['notnull']}|'
          '${r['dflt_value']}|${r['pk']}')
      .toSet();
}

void main() {
  sqfliteFfiInit();
  final factory = databaseFactoryFfi;

  // Own temp directory per run: other test files share the default
  // fuelpulse.db through DatabaseHelper(), and test files run concurrently.
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('fuelpulse_db_');
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
  });

  Future<Database> openFresh(String name) => factory.openDatabase(
        join(dir.path, name),
        options: OpenDatabaseOptions(
          version: DatabaseHelper.schemaVersion,
          onCreate: DatabaseHelper.onCreate,
        ),
      );

  Future<Database> openUpgradedFromV1(String name,
      {Map<String, Object?>? legacyRow}) async {
    final path = join(dir.path, name);
    final v1 = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute(_v1CreateTable),
      ),
    );
    if (legacyRow != null) await v1.insert('fuel_logs', legacyRow);
    await v1.close();

    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: DatabaseHelper.schemaVersion,
        onUpgrade: DatabaseHelper.onUpgrade,
      ),
    );
  }

  test('upgrade from v1 keeps legacy rows and gives them the defaults',
      () async {
    final db = await openUpgradedFromV1('upgrade.db', legacyRow: {
      'id': 'legacy',
      'timestamp': '2025-01-01T00:00:00.000',
      'odometer': 5000,
      'liters': 20.0,
      'pumpBrand': 'HP',
      'fullTank': 1,
      'notes': '',
    });

    expect(await db.getVersion(), DatabaseHelper.schemaVersion);
    final restored = FuelLog.fromMap((await db.query('fuel_logs')).single);
    expect(restored.odometer, 5000);
    expect(restored.liters, 20.0);
    expect(restored.pumpBrand, 'HP');
    expect(restored.fuelType, 'Normal');
    expect(restored.totalCost, isNull);
    expect(restored.pricePerLitre, isNull);
    await db.close();
  });

  test('upgraded schema matches a fresh install', () async {
    final upgraded = await openUpgradedFromV1('upgraded.db');
    final fresh = await openFresh('fresh.db');

    expect(await _columns(upgraded), await _columns(fresh));

    await upgraded.close();
    await fresh.close();
  });

  test('fresh install stores and returns every field', () async {
    final db = await openFresh('roundtrip.db');
    final log = FuelLog(
      id: 'full',
      timestamp: '2026-08-01T09:00:00.000',
      odometer: 12000,
      liters: 23.92,
      pumpBrand: 'Indian Oil',
      fullTank: false,
      notes: 'highway',
      fuelType: 'XP-95',
      totalCost: 2500.0,
      pricePerLitre: 104.5,
    );
    await db.insert('fuel_logs', log.toMap());

    final restored = FuelLog.fromMap((await db.query('fuel_logs')).single);
    expect(restored.toMap(), log.toMap());
    await db.close();
  });
}
