import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fuelpulse/db/database_helper.dart';
import 'package:fuelpulse/models/fuel_log.dart';
import 'package:fuelpulse/models/vehicle.dart';
import 'package:fuelpulse/models/theme_preference.dart';
import 'package:fuelpulse/screens/settings_screen.dart';
import 'package:fuelpulse/utils/fuel_type_manager.dart' as ftm;
import 'package:fuelpulse/utils/pump_brand_manager.dart' as pbm;

// Pins down what Settings does, so the split into section files can be
// checked against it.

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

Future<void> _tapVisible(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await _settle(tester);
}

/// Types into the open name dialog and presses Save.
Future<void> _submitDialog(WidgetTester tester, String text) async {
  await tester.enterText(
      find.descendant(
          of: find.byType(AlertDialog), matching: find.byType(TextField)),
      text);
  await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(ElevatedButton, 'Save')));
  await _settle(tester);
}

/// The page's own vertical scroll view (the theme swatches scroll too).
final _page = find.byType(Scrollable).first;

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    await databaseFactory.setDatabasesPath(
        Directory.systemTemp.createTempSync('fuelpulse_settings_').path);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await _db.resetToDefaultVehicle();
  });

  testWidgets('every section renders', (tester) async {
    await _pumpSettings(tester);
    for (final header in [
      'Vehicles',
      'Fuel Types',
      'Pump Brands',
      'Data Management',
      'Theme Color',
      'About',
      'Danger Zone',
    ]) {
      await tester.scrollUntilVisible(find.text(header), 200,
          scrollable: _page);
      expect(find.text(header), findsOneWidget, reason: header);
    }
  });

  testWidgets('adds and renames a fuel type', (tester) async {
    await _pumpSettings(tester);

    await _tapVisible(tester, find.text('Add fuel type'));
    await _submitDialog(tester, 'XP-95');
    expect(await _real(tester, ftm.loadFuelTypes), ['Normal', 'XP-95']);

    final editXp = find.descendant(
      of: find.ancestor(of: find.text('XP-95'), matching: find.byType(Row)),
      matching: find.byIcon(Icons.edit_outlined),
    );
    await _tapVisible(tester, editXp.first);
    await _submitDialog(tester, 'Speed 97');
    expect(await _real(tester, ftm.loadFuelTypes), ['Normal', 'Speed 97']);
  });

  testWidgets('adds a pump brand and renames it on existing logs',
      (tester) async {
    await _pumpSettings(tester);

    await _tapVisible(tester, find.text('Add pump brand'));
    await _submitDialog(tester, 'Reliance');
    expect(await _real(tester, pbm.loadPumpBrands), contains('Reliance'));

    await _real(
        tester,
        () => _db.insertLog(_logFor('r1', 'Reliance')));
    final editReliance = find.descendant(
      of: find.ancestor(of: find.text('Reliance'), matching: find.byType(Row)),
      matching: find.byIcon(Icons.edit_outlined),
    );
    await _tapVisible(tester, editReliance.first);
    await _submitDialog(tester, 'Jio');
    expect(await _real(tester, pbm.loadPumpBrands), contains('Jio'));
    final log = await _real(tester, () => _db.getLogById('r1'));
    expect(log!.pumpBrand, 'Jio');
  });

  testWidgets('Danger Zone wipes data only after DELETE is typed',
      (tester) async {
    await _real(tester, () async {
      await _db.insertVehicle(const Vehicle(
          id: 'bike', name: 'Activa', createdAt: '2026-01-01'));
      await _db.insertLog(_logFor('x', 'HP'));
    });
    await _pumpSettings(tester);

    await _tapVisible(tester, find.text('Danger Zone'));
    expect(find.textContaining('Type DELETE to confirm'), findsOneWidget);

    await _tapVisible(tester, find.text('Delete All Data'));
    expect(await _real(tester, _db.getLogCount), 1);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Type DELETE'), 'DELETE');
    await _tapVisible(tester, find.text('Delete All Data'));
    expect(await _real(tester, _db.getLogCount), 0);
    // Every vehicle goes, and one default vehicle is left to log into.
    expect((await _real(tester, _db.getVehicles)).map((v) => v.id),
        [kDefaultVehicleId]);
    // The Vehicles section on screen follows: no deleted vehicle lingers.
    await _settle(tester);
    expect(find.text('Activa'), findsNothing);
    expect(find.text(kDefaultVehicleName), findsOneWidget);
  });
}

FuelLog _logFor(String id, String brand) => FuelLog(
      vehicleId: kDefaultVehicleId,
      id: id,
      timestamp: '2026-08-01T09:00:00.000',
      odometer: 1000,
      liters: 20,
      pumpBrand: brand,
    );
