import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fuelpulse/db/database_helper.dart';
import 'package:fuelpulse/models/attachment.dart';
import 'package:fuelpulse/models/fuel_log.dart';
import 'package:fuelpulse/models/trip.dart';
import 'package:fuelpulse/models/vehicle.dart';
import 'package:fuelpulse/utils/undo_delete.dart' show attachmentsOf;

// What Undo after a delete relies on: the rows read before the delete
// come back exactly, including the links the delete changed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  setUpAll(() async {
    await databaseFactory.setDatabasesPath(
        Directory.systemTemp.createTempSync('fuelpulse_undo_').path);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseHelper().resetToDefaultVehicle();
  });

  FuelLog log(String id, {String? tripId}) => FuelLog(
        vehicleId: kDefaultVehicleId,
        id: id,
        timestamp: '2026-10-01T09:00:00.000',
        odometer: 12000,
        liters: 5,
        pumpBrand: 'Shell',
        fuelType: 'Normal',
        tripId: tripId,
      );

  test('a deleted fill-up comes back with its bill', () async {
    final db = DatabaseHelper();
    await db.insertLogs([log('f1')]);
    await db.saveAttachment(const Attachment(
        id: 'a1',
        ownerType: 'fuel',
        ownerId: 'f1',
        file: 'bill.jpg',
        kind: 'image',
        createdAt: '2026-10-01T09:00:00.000'));
    final saved = await db.snapshotRows({
      'fuel_logs': ('id = ?', ['f1']),
      'attachments': attachmentsOf('fuel', 'f1'),
    });

    expect(await db.deleteLog('f1'), ['bill.jpg']);
    expect(await db.getLogById('f1'), isNull);

    await db.restoreRows(saved);
    expect((await db.getLogById('f1'))?.odometer, 12000);
    expect([for (final a in await db.getAttachments('fuel', 'f1')) a.file],
        ['bill.jpg']);
  });

  test('a deleted trip comes back with its fill-ups on it again', () async {
    final db = DatabaseHelper();
    await db.saveTrip(const Trip(
        id: 't1',
        vehicleId: kDefaultVehicleId,
        name: 'Ooty',
        startAt: '2026-10-01T07:00:00.000',
        startOdometer: 11900));
    await db.insertLogs([log('f1', tripId: 't1')]);
    final saved = await db.snapshotRows({
      'trips': ('id = ?', ['t1']),
      'fuel_logs': ('tripId = ?', ['t1']),
    });

    await db.deleteTrip('t1');
    expect((await db.getLogById('f1'))?.tripId, isNull);

    await db.restoreRows(saved);
    expect((await db.getTrip('t1'))?.name, 'Ooty');
    expect((await db.getLogById('f1'))?.tripId, 't1');
  });
}
