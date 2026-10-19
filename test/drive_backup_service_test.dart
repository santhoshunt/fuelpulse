import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fuelpulse/db/database_helper.dart';
import 'package:fuelpulse/services/drive_backup_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  // Own database file: test files run in parallel processes, and the
  // default path is shared by every file that does not set one.
  setUpAll(() async {
    await databaseFactory.setDatabasesPath(
        Directory.systemTemp.createTempSync('fuelpulse_drive_backup_service_').path);
  });

  group('isDue', () {
    final now = DateTime(2026, 8, 10, 9);

    test('never backed up → due', () {
      expect(DriveBackupService.isDue(null, 'daily', now), isTrue);
    });

    test('clock moved backwards (future last) → due', () {
      expect(
        DriveBackupService.isDue(
            now.add(const Duration(days: 2)), 'daily', now),
        isTrue,
      );
    });

    test('daily: due after 23h, not before', () {
      expect(
        DriveBackupService.isDue(
            now.subtract(const Duration(hours: 23)), 'daily', now),
        isTrue,
      );
      expect(
        DriveBackupService.isDue(
            now.subtract(const Duration(hours: 22)), 'daily', now),
        isFalse,
      );
    });

    test('weekly: due after 6 days, not before', () {
      expect(
        DriveBackupService.isDue(
            now.subtract(const Duration(days: 6)), 'weekly', now),
        isTrue,
      );
      expect(
        DriveBackupService.isDue(
            now.subtract(const Duration(days: 5)), 'weekly', now),
        isFalse,
      );
    });

    test('monthly: due after 28 days, not before', () {
      expect(
        DriveBackupService.isDue(
            now.subtract(const Duration(days: 28)), 'monthly', now),
        isTrue,
      );
      expect(
        DriveBackupService.isDue(
            now.subtract(const Duration(days: 27)), 'monthly', now),
        isFalse,
      );
    });

    test('unknown frequency falls back to daily', () {
      expect(
        DriveBackupService.isDue(
            now.subtract(const Duration(days: 1)), 'bogus', now),
        isTrue,
      );
    });
  });

  group('gzip payload codec', () {
    test('a payload survives encode → decode intact', () {
      final data = {
        'app': 'fuelpulse',
        'version': 1,
        'logs': [
          {'id': '1', 'odometer': 1000, 'liters': 10.5, 'fuelType': 'XP-95'},
        ],
        'fuelTypes': ['Normal', 'XP-95'],
      };
      final decoded = decodeBackupGz(encodeBackupGz(data));
      expect(decoded['app'], 'fuelpulse');
      expect((decoded['logs'] as List).single['fuelType'], 'XP-95');
      expect(decoded['fuelTypes'], ['Normal', 'XP-95']);
    });

    test('garbage bytes are rejected with FormatException', () {
      expect(
        () => decodeBackupGz(Uint8List.fromList([1, 2, 3, 4, 5])),
        throwsFormatException,
      );
    });
  });

  group('backup file name', () {
    test('is prefix-matched, iso-sortable, and extension-tagged', () {
      final name =
          DriveBackupService.backupFileName(DateTime(2026, 8, 10, 9, 5, 3));
      expect(name, 'fuelpulse_backup_2026-08-10T09-05-03.json.gz');
      final later =
          DriveBackupService.backupFileName(DateTime(2026, 8, 11, 8));
      expect(name.compareTo(later), lessThan(0));
    });
  });

  group('uploadNow race hardening', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('a second uploadNow joins the in-flight one', () async {
      final svc = DriveBackupService();
      final payload = {'app': 'fuelpulse', 'version': 1, 'logs': []};
      // No platform channel under tests → sign-in fails inside _api(), so
      // both futures reject — but they must be the SAME future.
      final f1 = svc.uploadNow(payload);
      final f2 = svc.uploadNow(payload);
      expect(identical(f1, f2), isTrue);
      await expectLater(f1, throwsA(anything));
      // After completion the slot is free again — a new call runs fresh.
      final f3 = svc.uploadNow(payload);
      expect(identical(f1, f3), isFalse);
      await expectLater(f3, throwsA(anything));
    });

    test('a failed upload records drive_last_error', () async {
      final svc = DriveBackupService();
      await expectLater(
        svc.uploadNow({'app': 'fuelpulse', 'version': 1, 'logs': []}),
        throwsA(anything),
      );
      expect(await svc.lastError(), isNotNull);
    });
  });

  group('checkAndRunScheduled', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await DatabaseHelper().deleteAllLogs();
    });

    test('empty database is a silent no-op — no plugin touched, no error',
        () async {
      final svc = DriveBackupService();
      await svc.checkAndRunScheduled();
      // The log-count guard returns before the sign-in plugin (which would
      // throw MissingPluginException here and land in lastError).
      expect(await svc.lastError(), isNull);
      expect(await svc.lastBackupAt(), isNull);
    });
  });
}
