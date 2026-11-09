import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fuelpulse/db/database_helper.dart';
import 'package:fuelpulse/models/fuel_log.dart';
import 'package:fuelpulse/models/vehicle.dart';
import 'package:fuelpulse/utils/odometer_reading.dart';

// The reading reminder's Enter km reply, without the notification.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  setUpAll(() async {
    await databaseFactory.setDatabasesPath(
        Directory.systemTemp.createTempSync('fuelpulse_typed_reading_').path);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseHelper().resetToDefaultVehicle();
    await DatabaseHelper().insertLogs([
      FuelLog(
        vehicleId: kDefaultVehicleId,
        id: 'f1',
        timestamp: '2026-10-01T09:00:00.000',
        odometer: 20000,
        liters: 5,
        pumpBrand: 'Shell',
        fuelType: 'Normal',
      ),
    ]);
  });

  test('takes grouped digits and a trailing km', () async {
    final r = await saveTypedReading(kDefaultVehicleId, ' 23,456 km');
    expect(r.km, 23456);
    expect(r.error, isNull);
    expect((await loadReading(kDefaultVehicleId))?.km, 23456);
  });

  test('stops at a decimal point', () async {
    expect((await saveTypedReading(kDefaultVehicleId, '23456.7')).km, 23456);
  });

  test('turns down text with no number and saves nothing', () async {
    final r = await saveTypedReading(kDefaultVehicleId, 'soon');
    expect(r.km, isNull);
    expect(r.error, contains('in km'));
    expect(await loadReading(kDefaultVehicleId), isNull);
  });

  test('turns down a reading below the last fill-up', () async {
    final r = await saveTypedReading(kDefaultVehicleId, '19999');
    expect(r.km, isNull);
    expect(r.error, contains('20000'));
  });
}
