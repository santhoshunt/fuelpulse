import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fuelpulse/db/database_helper.dart';
import 'package:fuelpulse/models/fuel_log.dart';
import 'package:fuelpulse/services/backup_payload.dart';
import 'package:fuelpulse/utils/constants.dart';
import 'package:fuelpulse/utils/fuel_type_manager.dart';
import 'package:fuelpulse/utils/pump_brand_manager.dart';

FuelLog _log(String id, {int odometer = 1000, String fuelType = 'Normal'}) =>
    FuelLog(
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

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseHelper().deleteAllLogs();
  });

  test(
      'payload carries sentinel, version, logs, fuel types, pump brands, '
      'settings', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(kTankCapacityKey, 11.0);
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
    expect((payload['settings'] as Map)['tankCapacity'], 11.0);
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

    await restoreBackup(payload, replace: false);
    var prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble(kTankCapacityKey), isNull);
    expect(await loadFuelTypes(), ['Normal']);
    expect(await loadPumpBrands(), kDefaultPumpBrands);

    await restoreBackup(payload, replace: true);
    prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble(kTankCapacityKey), 12.5);
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
