import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fuelpulse/db/database_helper.dart';
import 'package:fuelpulse/models/attachment.dart';
import 'package:fuelpulse/models/check.dart';
import 'package:fuelpulse/models/fuel_log.dart';
import 'package:fuelpulse/models/service_record.dart';
import 'package:fuelpulse/models/vehicle.dart';
import 'package:fuelpulse/services/history_pdf.dart';
import 'package:fuelpulse/utils/custom_pictures.dart';
import 'package:fuelpulse/utils/vehicle_manager.dart';

// A 1x1 PNG, standing in for a bill photo.
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  late Directory tmp;
  setUpAll(() async {
    tmp = Directory.systemTemp.createTempSync('fuelpulse_history_pdf_');
    await databaseFactory.setDatabasesPath(tmp.path);
    picturesPath = tmp.path;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseHelper().resetToDefaultVehicle();
  });

  test('builds past the 20-page default with a bill photo appendix', () async {
    final db = DatabaseHelper();
    final start = DateTime(2022, 1, 1);
    // About four years of fill-ups: well over 20 pages of table rows.
    await db.insertLogs([
      for (var i = 0; i < 1200; i++)
        FuelLog(
          vehicleId: kDefaultVehicleId,
          id: 'f$i',
          timestamp: start.add(Duration(days: i)).toIso8601String(),
          odometer: 1000 + i * 40,
          liters: 4.5,
          pumpBrand: 'Shell',
          fuelType: 'Normal',
          totalCost: 470,
          pricePerLitre: 104.4,
          fullTank: i.isEven,
        ),
    ]);
    await db.insertService(const ServiceRecord(
        id: 's1',
        vehicleId: kDefaultVehicleId,
        timestamp: '2025-03-01T10:00:00.000',
        odometer: 20000,
        cost: 1850));
    await File('${tmp.path}/bill.png').writeAsBytes(_png);
    await db.saveAttachment(const Attachment(
        id: 'a1',
        ownerType: 'service',
        ownerId: 's1',
        file: 'bill.png',
        kind: 'image',
        createdAt: '2025-03-01T10:00:00.000'));

    await db.saveCheck(const Check(
        id: 'q1',
        vehicleId: kDefaultVehicleId,
        name: 'Tyre pressure',
        everyDays: 14,
        lastDoneAt: '2025-03-01T10:00:00.000',
        lastDoneKm: 20000));

    final bytes = await buildVehicleHistoryPdf(await loadActiveVehicle());
    expect(ascii.decode(bytes.sublist(0, 5)), '%PDF-');
    expect(bytes.length, greaterThan(50000));
  });
}
