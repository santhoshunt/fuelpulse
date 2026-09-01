import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fuelpulse/db/database_helper.dart';
import 'package:fuelpulse/models/fuel_log.dart';
import 'package:fuelpulse/utils/fuel_type_manager.dart';

FuelLog _log(String id, String fuelType) => FuelLog(
      id: id,
      timestamp: '2026-08-01T09:00:00.000',
      odometer: 1000,
      liters: 10,
      pumpBrand: 'Shell',
      fuelType: fuelType,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseHelper().deleteAllLogs();
  });

  test('absent prefs seed the default type', () async {
    expect(await loadFuelTypes(), ['Normal']);
  });

  test('add rejects empty and case-insensitive duplicates', () async {
    expect(await addFuelType('  '), isFalse);
    expect(await addFuelType('XP-95'), isTrue);
    expect(await addFuelType('xp-95'), isFalse);
    expect(await addFuelType('normal'), isFalse); // seeded default counts
    expect(await loadFuelTypes(), ['Normal', 'XP-95']);
  });

  test('rename preserves list order and updates existing logs', () async {
    await addFuelType('XP-95');
    await addFuelType('XP-100');
    final db = DatabaseHelper();
    await db.insertLogs([
      _log('1', 'XP-95'),
      _log('2', 'XP-95'),
      _log('3', 'Normal'),
    ]);

    final updated = await renameFuelType('XP-95', 'Extra Premium 95');
    expect(updated, 2);
    expect(await loadFuelTypes(), ['Normal', 'Extra Premium 95', 'XP-100']);
    expect((await db.getLogById('1'))!.fuelType, 'Extra Premium 95');
    expect((await db.getLogById('3'))!.fuelType, 'Normal');
  });

  test('rename rejects duplicates of another type', () async {
    await addFuelType('XP-95');
    expect(await renameFuelType('XP-95', 'normal'), -1);
    expect(await loadFuelTypes(), ['Normal', 'XP-95']);
  });

  test('delete removes from the list but leaves logs untouched', () async {
    await addFuelType('XP-95');
    final db = DatabaseHelper();
    await db.insertLogs([_log('1', 'XP-95')]);

    await deleteFuelType('XP-95');
    expect(await loadFuelTypes(), ['Normal']);
    expect((await db.getLogById('1'))!.fuelType, 'XP-95');
  });
}
