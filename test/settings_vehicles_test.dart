import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fuelpulse/db/database_helper.dart';
import 'package:fuelpulse/models/fuel_log.dart';
import 'package:fuelpulse/models/theme_preference.dart';
import 'package:fuelpulse/models/vehicle.dart';
import 'package:fuelpulse/screens/settings_screen.dart';

final _db = DatabaseHelper();

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
  await tester.pumpAndSettle();
}

Future<T> _real<T>(WidgetTester tester, Future<T> Function() fn) async =>
    (await tester.runAsync(fn)) as T;

Future<void> _pumpSettings(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: SettingsScreen(
      currentTheme: ThemePreference.defaults,
      onThemeChanged: (_) {},
    ),
  ));
  await _settle(tester);
}

Finder _dialogField(String label) => find.descendant(
    of: find.byType(AlertDialog),
    matching: find.widgetWithText(TextField, label));

Future<void> _saveDialog(WidgetTester tester) async {
  await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(ElevatedButton, 'Save')));
  await _settle(tester);
}

Finder _rowButton(String vehicleName, String tooltip) => find.descendant(
      of: find.ancestor(
          of: find.text(vehicleName), matching: find.byType(Row)),
      matching: find.byTooltip(tooltip),
    );

FuelLog _log(String id, String vehicleId) => FuelLog(
      vehicleId: vehicleId,
      id: id,
      timestamp: '2026-08-01T09:00:00.000',
      odometer: 1000,
      liters: 20,
      pumpBrand: 'HP',
    );

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    await databaseFactory.setDatabasesPath(
        Directory.systemTemp.createTempSync('fuelpulse_vehicles_').path);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await _db.resetToDefaultVehicle();
  });

  testWidgets('lists the default vehicle without a tank size',
      (tester) async {
    await _pumpSettings(tester);
    expect(find.text('Vehicles'), findsOneWidget);
    expect(find.text(kDefaultVehicleName), findsOneWidget);
    expect(find.text('Car · Tank size not set'), findsOneWidget);
  });

  testWidgets('adds a bike with a tank size', (tester) async {
    await _pumpSettings(tester);

    await tester.tap(find.text('Add vehicle'));
    await _settle(tester);
    await tester.enterText(_dialogField('Name'), 'Activa');
    await tester.tap(find.text('Bike'));
    await tester.pump();
    await tester.enterText(_dialogField('Tank size (optional)'), '5.3');
    await _saveDialog(tester);

    final vehicles = await _real(tester, _db.getVehicles);
    final bike = vehicles.singleWhere((v) => v.name == 'Activa');
    expect(bike.type, VehicleType.bike);
    expect(bike.tankCapacity, 5.3);
    expect(find.text('Bike · 5.3 L tank'), findsOneWidget);
  });

  testWidgets('an empty name is refused', (tester) async {
    await _pumpSettings(tester);
    await tester.tap(find.text('Add vehicle'));
    await _settle(tester);
    await _saveDialog(tester);

    expect(find.text('Enter a name'), findsOneWidget);
    expect(await _real(tester, _db.getVehicles), hasLength(1));
  });

  testWidgets('renames a vehicle and sets, then clears, its tank size',
      (tester) async {
    await _pumpSettings(tester);

    await tester.tap(_rowButton(kDefaultVehicleName, 'Edit vehicle'));
    await _settle(tester);
    await tester.enterText(_dialogField('Name'), 'Swift');
    await tester.enterText(_dialogField('Tank size (optional)'), '37');
    await _saveDialog(tester);

    var v = (await _real(tester, () => _db.getVehicle(kDefaultVehicleId)))!;
    expect(v.name, 'Swift');
    expect(v.tankCapacity, 37);
    expect(find.text('Car · 37 L tank'), findsOneWidget);

    await tester.tap(_rowButton('Swift', 'Edit vehicle'));
    await _settle(tester);
    await tester.enterText(_dialogField('Tank size (optional)'), '');
    await _saveDialog(tester);

    v = (await _real(tester, () => _db.getVehicle(kDefaultVehicleId)))!;
    expect(v.tankCapacity, isNull);
  });

  testWidgets('the last vehicle cannot be deleted', (tester) async {
    await _pumpSettings(tester);
    final delete = tester.widget<IconButton>(find.ancestor(
        of: _rowButton(kDefaultVehicleName,
            'Add another vehicle before deleting this one'),
        matching: find.byType(IconButton)));
    expect(delete.onPressed, isNull);
  });

  testWidgets('deleting a vehicle names its fill-ups and removes them',
      (tester) async {
    await _real(tester, () async {
      await _db.insertVehicle(const Vehicle(
          id: 'bike', name: 'Activa', sortOrder: 1, createdAt: '2026-08-01'));
      await _db.insertLogs([
        _log('b1', 'bike'),
        _log('b2', 'bike'),
        _log('c1', kDefaultVehicleId),
      ]);
    });
    await _pumpSettings(tester);

    await tester.tap(_rowButton('Activa', 'Delete vehicle'));
    await _settle(tester);
    expect(find.textContaining('This also deletes its 2 fill-ups'),
        findsOneWidget);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
    await _settle(tester);

    expect((await _real(tester, _db.getVehicles)).map((v) => v.id),
        [kDefaultVehicleId]);
    expect((await _real(tester, _db.getEveryLogChrono)).map((l) => l.id),
        ['c1']);
    expect(find.text('Activa'), findsNothing);
  });
}
