import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fuelpulse/db/database_helper.dart';
import 'package:fuelpulse/models/vehicle.dart';
import 'package:fuelpulse/utils/odometer_reading.dart';

// The odometer readings list: newest is current, delete and Undo, and a
// reading saved before 4.4 carried over.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  setUpAll(() async {
    await databaseFactory.setDatabasesPath(
        Directory.systemTemp.createTempSync('fuelpulse_readings_').path);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseHelper().resetToDefaultVehicle();
  });

  test('the newest reading is current, and deleting it goes back one',
      () async {
    await saveReading(kDefaultVehicleId, 1000);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    final second =
        await saveReading(kDefaultVehicleId, 1200, how: 'notification');
    expect((await loadReading(kDefaultVehicleId))?.km, 1200);
    final list = await loadReadings(kDefaultVehicleId);
    expect([for (final r in list) r.how], ['notification', 'typed']);

    await deleteReading(kDefaultVehicleId, second);
    expect((await loadReading(kDefaultVehicleId))?.km, 1000);

    await restoreReading(kDefaultVehicleId, list.first);
    expect((await loadReading(kDefaultVehicleId))?.km, 1200);
    expect((await loadReadings(kDefaultVehicleId)).length, 2);
  });

  test('a reading saved before the list is read as the first entry',
      () async {
    SharedPreferences.setMockInitialValues({
      'flutter.fuel_odometer_reading_$kDefaultVehicleId':
          jsonEncode({'km': 900, 'at': '2026-10-01T08:00:00.000'}),
    });
    expect((await loadReading(kDefaultVehicleId))?.km, 900);
    await saveReading(kDefaultVehicleId, 950);
    final list = await loadReadings(kDefaultVehicleId);
    expect([for (final r in list) r.km], [950, 900]);
  });
}
