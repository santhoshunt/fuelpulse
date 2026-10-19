import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fuelpulse/db/database_helper.dart';
import 'package:fuelpulse/models/fuel_log.dart';
import 'package:fuelpulse/models/vehicle.dart';
import 'package:fuelpulse/services/backup_payload.dart';
import 'package:fuelpulse/utils/constants.dart';
import 'package:fuelpulse/utils/fuel_type_manager.dart';
import 'package:fuelpulse/utils/pump_brand_manager.dart';
import 'package:fuelpulse/utils/vehicle_manager.dart';

const _bike = Vehicle(
    id: 'bike',
    name: 'Activa',
    type: VehicleType.bike,
    tankCapacity: 5.3,
    sortOrder: 1,
    createdAt: '2026-06-01T00:00:00.000');

FuelLog _log(String id,
        {int odometer = 1000,
        String fuelType = 'Normal',
        String vehicleId = kDefaultVehicleId}) =>
    FuelLog(
      vehicleId: vehicleId,
      id: id,
      timestamp: '2026-08-01T09:00:00.000',
      odometer: odometer,
      liters: 10,
      pumpBrand: 'Shell',
      fuelType: fuelType,
      totalCost: 1000,
      pricePerLitre: 100,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  // Own database file: test files run in parallel processes, and the
  // default path is shared by every file that does not set one.
  setUpAll(() async {
    await databaseFactory.setDatabasesPath(
        Directory.systemTemp.createTempSync('fuelpulse_backup_payload_').path);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseHelper().resetToDefaultVehicle();
  });

  test(
      'payload carries sentinel, version, logs, fuel types, pump brands, '
      'settings', () async {
    final db = DatabaseHelper();
    await db.insertVehicle(_bike);
    await setActiveVehicle('bike');
    await addFuelType('XP-95');
    await addPumpBrand('Reliance');
    await DatabaseHelper().insertLogs([_log('1'), _log('2', odometer: 1500)]);

    final payload = await buildBackupPayload();
    expect(payload['app'], 'fuelpulse');
    expect(payload['version'], kBackupVersion);
    expect((payload['logs'] as List).length, 2);
    // Costs travel inside each log map.
    expect(((payload['logs'] as List).first as Map)['totalCost'], 1000);
    expect(payload['fuelTypes'], ['Normal', 'XP-95']);
    expect(payload['pumpBrands'], [...kDefaultPumpBrands, 'Reliance']);
    expect((payload['vehicles'] as List).map((v) => (v as Map)['id']),
        [kDefaultVehicleId, 'bike']);
    expect((payload['settings'] as Map)['activeVehicleId'], 'bike');
    // Tank capacity lives on each vehicle now, not in settings.
    expect((payload['settings'] as Map).containsKey('tankCapacity'), isFalse);
  });

  test('replace wipes local logs and keeps original IDs', () async {
    final db = DatabaseHelper();
    await db.insertLogs([_log('device-only')]);
    final payload = {
      'app': 'fuelpulse',
      'version': 1,
      'logs': [_log('backup-1').toMap(), _log('backup-2').toMap()],
    };

    final count = await restoreBackup(payload, replace: true);
    expect(count, 2);
    expect(await db.getLogCount(), 2);
    expect(await db.getLogById('device-only'), isNull);
    expect(await db.getLogById('backup-1'), isNotNull);
  });

  test('merge keeps device rows and is idempotent (id-keyed)', () async {
    final db = DatabaseHelper();
    await db.insertLogs([_log('device-only')]);
    final payload = {
      'app': 'fuelpulse',
      'version': 1,
      'logs': [_log('backup-1').toMap()],
    };

    await restoreBackup(payload, replace: false);
    await restoreBackup(payload, replace: false); // second run adds nothing
    expect(await db.getLogCount(), 2);
    expect(await db.getLogById('device-only'), isNotNull);
  });

  test('settings, fuel types and pump brands apply on replace only',
      () async {
    final payload = {
      'app': 'fuelpulse',
      'version': 2,
      'logs': [_log('1').toMap()],
      'fuelTypes': ['Normal', 'XP-100'],
      'pumpBrands': ['Shell', 'Reliance'],
      'settings': {'tankCapacity': 12.5},
    };

    final db = DatabaseHelper();
    await restoreBackup(payload, replace: false);
    expect((await db.getVehicle(kDefaultVehicleId))!.tankCapacity, isNull);
    expect(await loadFuelTypes(), ['Normal']);
    expect(await loadPumpBrands(), kDefaultPumpBrands);

    await restoreBackup(payload, replace: true);
    // A v2 file's global tank capacity lands on the default vehicle.
    expect((await db.getVehicle(kDefaultVehicleId))!.tankCapacity, 12.5);
    expect(await loadFuelTypes(), ['Normal', 'XP-100']);
    expect(await loadPumpBrands(), ['Shell', 'Reliance']);
  });

  test('a v1 backup without pumpBrands restores cleanly on replace',
      () async {
    await addPumpBrand('Reliance');
    final payload = {
      'app': 'fuelpulse',
      'version': 1,
      'logs': [_log('1').toMap()],
      'fuelTypes': ['Normal'],
    };

    await restoreBackup(payload, replace: true);
    // Absent in the backup means the local list is left alone.
    expect(await loadPumpBrands(), [...kDefaultPumpBrands, 'Reliance']);
  });

  test('a v3 replace round-trips every vehicle and the active one',
      () async {
    final db = DatabaseHelper();
    await db.insertVehicle(_bike);
    await db.insertLogs([
      _log('car-1'),
      _log('bike-1', vehicleId: 'bike'),
    ]);
    await setActiveVehicle('bike');
    final payload = await buildBackupPayload();

    await db.resetToDefaultVehicle();
    SharedPreferences.setMockInitialValues({});
    final count = await restoreBackup(payload, replace: true);

    expect(count, 2);
    final vehicles = await db.getVehicles();
    expect(vehicles.map((v) => v.id), [kDefaultVehicleId, 'bike']);
    expect(vehicles.last.tankCapacity, 5.3);
    expect((await db.getLogById('bike-1'))!.vehicleId, 'bike');
    expect((await loadActiveVehicle()).id, 'bike');
  });

  test('a v2 replace puts every log in the default vehicle', () async {
    final db = DatabaseHelper();
    await db.insertVehicle(_bike);
    final legacy = _log('old').toMap()..remove('vehicleId');
    await restoreBackup({
      'app': 'fuelpulse',
      'version': 2,
      'logs': [legacy],
      'settings': {'tankCapacity': 40},
    }, replace: true);

    // Replace swaps vehicles too: the file had none, so only the default.
    expect((await db.getVehicles()).map((v) => v.id), [kDefaultVehicleId]);
    expect((await db.getLogById('old'))!.vehicleId, kDefaultVehicleId);
    expect((await db.getVehicle(kDefaultVehicleId))!.tankCapacity, 40);
  });

  test('merge adds new vehicles and maps unknown vehicles to the default',
      () async {
    final db = DatabaseHelper();
    await restoreBackup({
      'app': 'fuelpulse',
      'version': 3,
      'vehicles': [_bike.toMap()],
      'logs': [
        _log('b1', vehicleId: 'bike').toMap(),
        _log('ghost', vehicleId: 'never-saved').toMap(),
      ],
    }, replace: false);

    expect((await db.getVehicles()).map((v) => v.id),
        [kDefaultVehicleId, 'bike']);
    expect((await db.getLogById('b1'))!.vehicleId, 'bike');
    expect((await db.getLogById('ghost'))!.vehicleId, kDefaultVehicleId);
  });

  test('merging an old file re-creates a deleted default vehicle',
      () async {
    final db = DatabaseHelper();
    await db.insertVehicle(_bike);
    await db.deleteVehicle(kDefaultVehicleId);

    await restoreBackup({
      'app': 'fuelpulse',
      'version': 2,
      'logs': [_log('old').toMap()..remove('vehicleId')],
    }, replace: false);

    expect(await db.getVehicle(kDefaultVehicleId), isNotNull);
    expect((await db.getLogById('old'))!.vehicleId, kDefaultVehicleId);
  });

  test('a backup from a newer FuelPulse is refused before any write',
      () async {
    final db = DatabaseHelper();
    await db.insertLogs([_log('keep-me')]);

    await expectLater(
      restoreBackup({
        'app': 'fuelpulse',
        'version': kBackupVersion + 1,
        'logs': [_log('future').toMap()],
      }, replace: true),
      throwsA(isA<FormatException>().having(
          (e) => e.message, 'message', contains('newer FuelPulse'))),
    );
    expect(await db.getLogById('keep-me'), isNotNull);
    expect(await db.getLogById('future'), isNull);
  });

  test('wrong app sentinel throws FormatException', () async {
    expect(
      () => restoreBackup({'app': 'expense_tracker', 'logs': []},
          replace: true),
      throwsFormatException,
    );
  });

  test('one malformed log rejects the whole file with no state change',
      () async {
    final db = DatabaseHelper();
    await db.insertLogs([_log('keep-me')]);
    final payload = {
      'app': 'fuelpulse',
      'version': 1,
      'logs': [
        _log('good').toMap(),
        {'id': 'bad'}, // missing every required field
      ],
    };

    await expectLater(
        restoreBackup(payload, replace: true), throwsFormatException);
    // Replace-mode wipe must not have happened.
    expect(await db.getLogById('keep-me'), isNotNull);
    expect(await db.getLogById('good'), isNull);
  });
}
