import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fuelpulse/db/database_helper.dart';
import 'package:fuelpulse/models/vehicle.dart';
import 'package:fuelpulse/utils/constants.dart';
import 'package:fuelpulse/utils/vehicle_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final db = DatabaseHelper();

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    await databaseFactory.setDatabasesPath(
        Directory.systemTemp.createTempSync('fuelpulse_vm_').path);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await db.resetToDefaultVehicle();
  });

  Vehicle bike() => const Vehicle(
      id: 'bike', name: 'Activa', sortOrder: 1, createdAt: '2026-08-01');

  test('defaults to the first vehicle when none is stored', () async {
    expect((await loadActiveVehicle()).id, kDefaultVehicleId);
  });

  test('the stored active vehicle is loaded back', () async {
    await db.insertVehicle(bike());
    await setActiveVehicle('bike');
    expect((await loadActiveVehicle()).name, 'Activa');
  });

  test('falls back when the stored vehicle is gone', () async {
    await db.insertVehicle(bike());
    await setActiveVehicle('bike');
    await db.deleteVehicle('bike');
    expect((await loadActiveVehicle()).id, kDefaultVehicleId);
  });

  test('legacy tank capacity moves onto the default vehicle', () async {
    SharedPreferences.setMockInitialValues({kTankCapacityKey: 37.0});
    await migrateLegacyTankCapacity();

    expect((await db.getVehicle(kDefaultVehicleId))!.tankCapacity, 37.0);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble(kTankCapacityKey), isNull);
  });

  test('migration never overwrites a capacity already set', () async {
    final v = await db.getVehicle(kDefaultVehicleId);
    await db.updateVehicle(v!.copyWith(tankCapacity: 45));
    SharedPreferences.setMockInitialValues({kTankCapacityKey: 37.0});

    await migrateLegacyTankCapacity();

    expect((await db.getVehicle(kDefaultVehicleId))!.tankCapacity, 45);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble(kTankCapacityKey), isNull);
  });

  test('migration does nothing without the legacy preference', () async {
    await migrateLegacyTankCapacity();
    expect((await db.getVehicle(kDefaultVehicleId))!.tankCapacity, isNull);
  });
}
