import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fuelpulse/db/database_helper.dart';
import 'package:fuelpulse/models/fuel_log.dart';
import 'package:fuelpulse/utils/constants.dart';
import 'package:fuelpulse/utils/pump_brand_manager.dart';

FuelLog _log(String id, String brand) => FuelLog(
      id: id,
      timestamp: '2026-08-01T09:00:00.000',
      odometer: 1000,
      liters: 10,
      pumpBrand: brand,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseHelper().deleteAllLogs();
  });

  test('absent prefs seed the default brand list', () async {
    expect(await loadPumpBrands(), kDefaultPumpBrands);
  });

  test('add rejects empty and case-insensitive duplicates', () async {
    expect(await addPumpBrand('  '), isFalse);
    expect(await addPumpBrand('Reliance'), isTrue);
    expect(await addPumpBrand('reliance'), isFalse);
    expect(await addPumpBrand('shell'), isFalse); // seeded default counts
    expect(await loadPumpBrands(), [...kDefaultPumpBrands, 'Reliance']);
  });

  test('rename preserves list order and updates existing logs', () async {
    await addPumpBrand('Reliance');
    final db = DatabaseHelper();
    await db.insertLogs([
      _log('1', 'Reliance'),
      _log('2', 'Reliance'),
      _log('3', 'Shell'),
    ]);

    final updated = await renamePumpBrand('Reliance', 'Jio-BP Reliance');
    expect(updated, 2);
    expect(
        await loadPumpBrands(), [...kDefaultPumpBrands, 'Jio-BP Reliance']);
    expect((await db.getLogById('1'))!.pumpBrand, 'Jio-BP Reliance');
    expect((await db.getLogById('3'))!.pumpBrand, 'Shell');
  });

  test('rename rejects duplicates of another brand', () async {
    await addPumpBrand('Reliance');
    expect(await renamePumpBrand('Reliance', 'shell'), -1);
    expect(await loadPumpBrands(), [...kDefaultPumpBrands, 'Reliance']);
  });

  test('delete removes from the list but leaves logs untouched', () async {
    final db = DatabaseHelper();
    await db.insertLogs([_log('1', 'Shell')]);

    await deletePumpBrand('Shell');
    expect((await loadPumpBrands()).contains('Shell'), isFalse);
    expect((await db.getLogById('1'))!.pumpBrand, 'Shell');
  });

  test('unknown brand gets an initials badge config', () {
    final config = getBrandConfig('Reliance Petroleum');
    expect(config.abbreviation, 'RP');
    expect(getBrandConfig('Essar').abbreviation, 'E');
    // Known brands and the empty/Other fallback are untouched.
    expect(getBrandConfig('shell').name, 'Shell');
    expect(getBrandConfig('').abbreviation, kOtherBrand.abbreviation);
  });
}
