import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fuelpulse/db/database_helper.dart';
import 'package:fuelpulse/models/fuel_log.dart';
import 'package:fuelpulse/models/vehicle.dart';
import 'package:fuelpulse/utils/brand_grades.dart';
import 'package:fuelpulse/utils/constants.dart';

// Replaces the v2.x fuel_type_manager and pump_brand_manager tests: the
// same behaviours, now on one brand-to-grades map.

final _db = DatabaseHelper();

FuelLog _log(String id, String brand, String grade) => FuelLog(
      vehicleId: kDefaultVehicleId,
      id: id,
      timestamp: '2026-08-0${id.length}T09:00:00.000',
      odometer: 1000,
      liters: 20,
      pumpBrand: brand,
      fuelType: grade,
    );

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    await databaseFactory.setDatabasesPath(
        Directory.systemTemp.createTempSync('fuelpulse_brand_grades_').path);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await _db.resetToDefaultVehicle();
  });

  test('a fresh install seeds the known brands, Normal first', () async {
    final map = await loadBrandGrades();
    expect(map.keys, kDefaultPumpBrands);
    expect(map['Shell'], ['Normal', 'E20', 'V-Power']);
    expect(map['Bharat Petroleum'],
        ['Normal', 'E20', 'Speed', 'Speed 97', 'Speed 100']);
  });

  test('an upgrade seeds from the v2.x lists', () async {
    SharedPreferences.setMockInitialValues({
      kPumpBrandsKey: ['Shell', 'Reliance'],
      kFuelTypesKey: ['Normal', 'XP-95'],
    });
    final map = await loadBrandGrades();
    expect(map.keys, ['Shell', 'Reliance']);
    expect(map['Shell'], ['Normal', 'XP-95', 'E20', 'V-Power']);
    expect(map['Reliance'], ['Normal', 'XP-95']);
  });

  test('adding a brand refuses a duplicate in another case', () async {
    expect(await addBrand(' Reliance '), isTrue);
    expect(await addBrand('reliance'), isFalse);
    expect(await addBrand('  '), isFalse);
    final map = await loadBrandGrades();
    expect(map.keys.last, 'Reliance');
    expect(map['Reliance'], [kDefaultFuelType]);
  });

  test('renaming a brand keeps its place and updates logs and pumps',
      () async {
    await _db.insertLogs([_log('a', 'HP', 'Normal'), _log('bb', 'Shell', 'E20')]);
    final updated = await renameBrand('HP', 'HPCL');
    expect(updated, 1);
    final map = await loadBrandGrades();
    expect(map.keys.elementAt(1), 'HPCL');
    expect((await _db.getLogById('a'))!.pumpBrand, 'HPCL');
    expect((await _db.getPumps()).map((p) => p.brand), contains('HPCL'));
    expect(await renameBrand('HPCL', 'shell'), -1);
  });

  test('deleting a brand keeps it on logs', () async {
    await _db.insertLogs([_log('a', 'HP', 'Normal')]);
    await deleteBrand('HP');
    expect((await loadBrandGrades()).containsKey('HP'), isFalse);
    expect((await _db.getLogById('a'))!.pumpBrand, 'HP');
  });

  test('grades are per brand: add, rename only that brand, delete',
      () async {
    expect(await addGrade('Shell', 'XP-95'), isTrue);
    expect(await addGrade('Shell', 'xp-95'), isFalse);
    await _db.insertLogs([
      _log('a', 'Shell', 'XP-95'),
      _log('bb', 'HP', 'XP-95'),
    ]);
    expect(await renameGrade('Shell', 'XP-95', 'V-Power 95'), 1);
    expect((await _db.getLogById('a'))!.fuelType, 'V-Power 95');
    expect((await _db.getLogById('bb'))!.fuelType, 'XP-95');
    expect(await renameGrade('Shell', 'V-Power 95', 'e20'), -1);
    await deleteGrade('Shell', 'V-Power 95');
    expect((await loadBrandGrades())['Shell'], isNot(contains('V-Power 95')));
    expect((await _db.getLogById('a'))!.fuelType, 'V-Power 95');
  });
}
