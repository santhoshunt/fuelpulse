import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fuelpulse/db/database_helper.dart';
import 'package:fuelpulse/models/fuel_log.dart';
import 'package:fuelpulse/services/backup_codec.dart';
import 'package:fuelpulse/services/backup_file.dart';
import 'package:fuelpulse/services/backup_payload.dart';
import 'package:fuelpulse/services/drive_backup_service.dart';
import 'package:fuelpulse/utils/constants.dart';
import 'package:fuelpulse/utils/fuel_type_manager.dart';
import 'package:fuelpulse/utils/pump_brand_manager.dart';

FuelLog _log(String id, {int odometer = 1000}) => FuelLog(
      id: id,
      timestamp: '2026-08-01T09:00:00.000',
      odometer: odometer,
      liters: 10,
      pumpBrand: 'Shell',
      fuelType: 'XP-95',
      totalCost: 1050,
      pricePerLitre: 105,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseHelper().deleteAllLogs();
  });

  test('file round-trip restores logs, settings, fuel types and brands',
      () async {
    final db = DatabaseHelper();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(kTankCapacityKey, 11.5);
    await addFuelType('XP-95');
    await addPumpBrand('Reliance');
    await db.insertLogs([_log('a'), _log('b', odometer: 1200)]);

    // Payload -> gzip -> real temp file, exactly what exportBackupFile shares.
    final payload = await buildBackupPayload();
    final file = File(
        '${Directory.systemTemp.path}/${buildBackupFileName(DateTime(2026, 9, 1, 14, 30))}');
    await file.writeAsBytes(encodeBackupGz(payload));
    addTearDown(() => file.delete());

    // Wipe everything, then restore from the file.
    await db.deleteAllLogs();
    SharedPreferences.setMockInitialValues({});

    final data = await readBackupFile(file);
    final restored = await restoreBackup(data, replace: true);

    expect(restored, 2);
    expect(await db.getLogCount(), 2);
    final a = await db.getLogById('a');
    expect(a!.totalCost, 1050);
    expect(a.fuelType, 'XP-95');
    final freshPrefs = await SharedPreferences.getInstance();
    expect(freshPrefs.getDouble(kTankCapacityKey), 11.5);
    expect(await loadFuelTypes(), ['Normal', 'XP-95']);
    expect(await loadPumpBrands(), [...kDefaultPumpBrands, 'Reliance']);
  });

  test('merge through the file path is id-keyed and idempotent', () async {
    final db = DatabaseHelper();
    await db.insertLogs([_log('device-only')]);

    final file =
        File('${Directory.systemTemp.path}/fuelpulse_merge_test.json.gz');
    await file.writeAsBytes(encodeBackupGz({
      'app': 'fuelpulse',
      'version': 2,
      'logs': [_log('from-backup').toMap()],
    }));
    addTearDown(() => file.delete());

    final data = await readBackupFile(file);
    await restoreBackup(data, replace: false);
    await restoreBackup(data, replace: false);
    expect(await db.getLogCount(), 2);
    expect(await db.getLogById('device-only'), isNotNull);
  });

  test('non-backup file is rejected with FormatException', () async {
    final file = File('${Directory.systemTemp.path}/not_a_backup.csv');
    await file.writeAsString('id,odometer,liters\n1,1000,10\n');
    addTearDown(() => file.delete());

    await expectLater(readBackupFile(file), throwsFormatException);
  });

  test('gzipped non-map JSON is rejected', () async {
    final file = File('${Directory.systemTemp.path}/list_backup.json.gz');
    await file.writeAsBytes(gzip.encode('[1,2,3]'.codeUnits));
    addTearDown(() => file.delete());

    await expectLater(readBackupFile(file), throwsFormatException);
  });

  test('static and top-level backup file names agree', () {
    final t = DateTime(2026, 9, 1, 14, 30, 5);
    expect(DriveBackupService.backupFileName(t), buildBackupFileName(t));
    expect(buildBackupFileName(t), startsWith(backupFilePrefix));
    expect(buildBackupFileName(t), isNot(contains(':')));
    expect(buildBackupFileName(t), endsWith('.json.gz'));
  });
}
