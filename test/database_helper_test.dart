import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' show join;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fuelpulse/db/database_helper.dart';
import 'package:fuelpulse/models/fuel_log.dart';
import 'package:fuelpulse/models/vehicle.dart';

// Frozen history: these are what real installs have on disk, so they must
// never track onCreate.

// Schema version 1, as shipped in the first release.
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

// Schema version 2, as shipped in v1.1.0 to v1.3.0.
const _v2CreateTable = '''
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
''';

const _legacyRow = {
  'id': 'legacy',
  'timestamp': '2025-01-01T00:00:00.000',
  'odometer': 5000,
  'liters': 20.0,
  'pumpBrand': 'HP',
  'fullTank': 1,
  'notes': '',
};

/// Column descriptions from PRAGMA table_info, as comparable strings.
Future<Set<String>> _columns(Database db, String table) async {
  final rows = await db.rawQuery('PRAGMA table_info($table)');
  return rows
      .map((r) => '${r['name']}|${r['type']}|${r['notnull']}|'
          '${r['dflt_value']}|${r['pk']}')
      .toSet();
}

Future<Set<String>> _indexes(Database db) async {
  final rows = await db.rawQuery('PRAGMA index_list(fuel_logs)');
  return rows
      .map((r) => r['name'] as String)
      .where((n) => !n.startsWith('sqlite_autoindex'))
      .toSet();
}

/// A log whose row has a column the table lacks, so its insert fails.
class _BadLog extends FuelLog {
  _BadLog()
      : super(
          vehicleId: kDefaultVehicleId,
          id: 'bad',
          timestamp: '2026-01-01T00:00:00.000',
          odometer: 1,
          liters: 1,
          pumpBrand: '',
        );

  @override
  Map<String, dynamic> toMap() => {...super.toMap(), 'noSuchColumn': 1};
}

FuelLog _log(String id, String vehicleId, {int odometer = 1000}) => FuelLog(
      vehicleId: vehicleId,
      id: id,
      timestamp: '2026-08-01T09:00:00.000',
      odometer: odometer,
      liters: 20,
      pumpBrand: 'HP',
    );

Vehicle _vehicle(String id, String name) => Vehicle(
      id: id,
      name: name,
      createdAt: '2026-08-01T09:00:00.000',
    );

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

  /// Creates a database at [version] with [createSql], then reopens it at
  /// the current schema through the real upgrade.
  Future<Database> openUpgraded(String name,
      {required int version,
      required String createSql,
      Map<String, Object?>? legacyRow}) async {
    final path = join(dir.path, name);
    final old = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: version,
        onCreate: (db, _) => db.execute(createSql),
      ),
    );
    if (legacyRow != null) await old.insert('fuel_logs', legacyRow);
    await old.close();

    return factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: DatabaseHelper.schemaVersion,
        onUpgrade: DatabaseHelper.onUpgrade,
      ),
    );
  }

  group('schema', () {
    test('upgrade from v1 keeps legacy rows and gives them the defaults',
        () async {
      final db = await openUpgraded('upgrade1.db',
          version: 1, createSql: _v1CreateTable, legacyRow: _legacyRow);

      expect(await db.getVersion(), DatabaseHelper.schemaVersion);
      final restored = FuelLog.fromMap((await db.query('fuel_logs')).single);
      expect(restored.odometer, 5000);
      expect(restored.liters, 20.0);
      expect(restored.pumpBrand, 'HP');
      expect(restored.fuelType, 'Normal');
      expect(restored.totalCost, isNull);
      expect(restored.pricePerLitre, isNull);
      expect(restored.vehicleId, kDefaultVehicleId);
      await db.close();
    });

    test('upgrade from v2 puts every log in "My vehicle"', () async {
      final db = await openUpgraded('upgrade2.db',
          version: 2,
          createSql: _v2CreateTable,
          legacyRow: {..._legacyRow, 'fuelType': 'XP-95', 'totalCost': 2000.0});

      final restored = FuelLog.fromMap((await db.query('fuel_logs')).single);
      expect(restored.vehicleId, kDefaultVehicleId);
      expect(restored.fuelType, 'XP-95');
      expect(restored.totalCost, 2000.0);

      final vehicles = await db.query('vehicles');
      expect(vehicles, hasLength(1));
      final v = Vehicle.fromMap(vehicles.single);
      expect(v.id, kDefaultVehicleId);
      expect(v.name, kDefaultVehicleName);
      expect(v.tankCapacity, isNull);
      await db.close();
    });

    for (final from in [1, 2]) {
      test('schema upgraded from v$from matches a fresh install', () async {
        final upgraded = await openUpgraded('upgraded$from.db',
            version: from,
            createSql: from == 1 ? _v1CreateTable : _v2CreateTable);
        final fresh = await openFresh('fresh$from.db');

        for (final table in ['fuel_logs', 'vehicles']) {
          expect(await _columns(upgraded, table), await _columns(fresh, table),
              reason: table);
        }
        expect(await _indexes(upgraded), await _indexes(fresh));
        expect(await _indexes(fresh), contains('idx_fuel_logs_vehicle'));

        await upgraded.close();
        await fresh.close();
      });
    }

    test('fresh install has exactly the default vehicle', () async {
      final db = await openFresh('fresh.db');
      final vehicles = await db.query('vehicles');
      expect(vehicles.map((v) => v['id']), [kDefaultVehicleId]);
      await db.close();
    });

    test('fresh install stores and returns every field', () async {
      final db = await openFresh('roundtrip.db');
      final log = FuelLog(
        vehicleId: 'bike',
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
  });

  group('DatabaseHelper', () {
    final db = DatabaseHelper();

    setUpAll(() async {
      databaseFactory = databaseFactoryFfiNoIsolate;
      await databaseFactory.setDatabasesPath(
          Directory.systemTemp.createTempSync('fuelpulse_helper_').path);
    });

    setUp(() => db.resetToDefaultVehicle());

    test('per-vehicle queries see only that vehicle', () async {
      await db.insertVehicle(_vehicle('bike', 'Activa'));
      await db.insertLogs([
        _log('c1', kDefaultVehicleId, odometer: 1000),
        _log('c2', kDefaultVehicleId, odometer: 1500),
        _log('b1', 'bike', odometer: 300),
      ]);

      expect((await db.getAllLogs('bike')).map((l) => l.id), ['b1']);
      expect((await db.getAllLogsChrono(kDefaultVehicleId)).map((l) => l.id),
          ['c1', 'c2']);
      expect((await db.getLastLog('bike'))!.odometer, 300);
      expect(await db.getLogCountFor('bike'), 1);
      expect(await db.getLogCount(), 3);
      expect(await db.getEveryLogChrono(), hasLength(3));
    });

    test('deleteVehicle removes only that vehicle and its logs', () async {
      await db.insertVehicle(_vehicle('bike', 'Activa'));
      await db.insertLogs([
        _log('c1', kDefaultVehicleId),
        _log('b1', 'bike'),
      ]);

      await db.deleteVehicle('bike');

      expect((await db.getVehicles()).map((v) => v.id), [kDefaultVehicleId]);
      expect((await db.getEveryLogChrono()).map((l) => l.id), ['c1']);
    });

    test('ensureDefaultVehicle re-creates a deleted default', () async {
      await db.insertVehicle(_vehicle('bike', 'Activa'));
      await db.deleteVehicle(kDefaultVehicleId);
      expect(await db.getVehicle(kDefaultVehicleId), isNull);

      await db.ensureDefaultVehicle();
      expect((await db.getVehicle(kDefaultVehicleId))!.name,
          kDefaultVehicleName);
    });

    test('replaceAllData swaps vehicles and logs together', () async {
      await db.insertLogs([_log('old', kDefaultVehicleId)]);

      await db.replaceAllData(
          [_vehicle('car', 'Swift'), _vehicle('bike', 'Activa')],
          [_log('n1', 'car'), _log('n2', 'bike')]);

      expect((await db.getVehicles()).map((v) => v.id), ['car', 'bike']);
      expect((await db.getEveryLogChrono()).map((l) => l.id),
          unorderedEquals(['n1', 'n2']));
    });

    test('replaceAllData rolls back when a log insert fails', () async {
      await db.insertLogs([_log('keep', kDefaultVehicleId)]);

      await expectLater(
          db.replaceAllData([_vehicle('car', 'Swift')],
              [_log('n1', 'car'), _BadLog()]),
          throwsA(anything));

      expect((await db.getVehicles()).map((v) => v.id), [kDefaultVehicleId]);
      expect((await db.getEveryLogChrono()).map((l) => l.id), ['keep']);
    });

    test('mergeData adds vehicles and logs together, or not at all',
        () async {
      await expectLater(
          db.mergeData([_vehicle('bike', 'Activa')],
              [_log('b1', 'bike'), _BadLog()]),
          throwsA(anything));
      expect((await db.getVehicles()).map((v) => v.id), [kDefaultVehicleId]);
      expect(await db.getLogCount(), 0);

      await db.mergeData([_vehicle('bike', 'Activa')], [_log('b1', 'bike')]);
      expect((await db.getVehicles()).map((v) => v.id),
          unorderedEquals([kDefaultVehicleId, 'bike']));
      expect(await db.getLogCountFor('bike'), 1);
    });

    test('mergeData ensureDefault keeps a renamed default vehicle', () async {
      final v = await db.getVehicle(kDefaultVehicleId);
      await db.updateVehicle(v!.copyWith(name: 'Swift'));

      await db.mergeData([], [_log('a', kDefaultVehicleId)],
          ensureDefault: true);

      expect((await db.getVehicle(kDefaultVehicleId))!.name, 'Swift');
    });

    test('mergeData keeps the file\'s own default vehicle over the generic one',
        () async {
      await db.insertVehicle(_vehicle('bike', 'Activa'));
      await db.deleteVehicle(kDefaultVehicleId);
      final fileDefault = Vehicle(
          id: kDefaultVehicleId,
          name: 'Swift',
          tankCapacity: 40,
          createdAt: '2026-06-01T00:00:00.000');

      await db.mergeData([fileDefault], [_log('a', kDefaultVehicleId)],
          ensureDefault: true);

      final v = (await db.getVehicle(kDefaultVehicleId))!;
      expect(v.name, 'Swift');
      expect(v.tankCapacity, 40);
    });

    test('replaceAllData with no vehicles keeps a default one', () async {
      await db.replaceAllData([], [_log('a', kDefaultVehicleId)]);
      expect((await db.getVehicles()).map((v) => v.id), [kDefaultVehicleId]);
    });
  });
}
