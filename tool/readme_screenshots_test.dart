// Renders the README screenshots offscreen. A generator, not a test: it lives
// outside test/ so `flutter test` (and CI) never runs it, and it reads fonts
// from this Windows machine. Run it by hand:
//
//   flutter test tool/readme_screenshots_test.dart --update-goldens
//
// Output: screenshots/dashboard.png, dashboard_dark.png, fuel.png,
// refill.png, add_fill_up.png, service.png, analytics.png, appearance.png.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' show join;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fuelpulse/db/database_helper.dart';
import 'package:fuelpulse/models/fuel_log.dart';
import 'package:fuelpulse/models/service_record.dart';
import 'package:fuelpulse/models/workshop.dart';
import 'package:fuelpulse/models/vehicle.dart';
import 'package:fuelpulse/screens/app_shell.dart';
import 'package:fuelpulse/theme/app_theme.dart';
import 'package:fuelpulse/theme/palettes.dart';

FuelLog _log(
  int n,
  String date,
  int odometer,
  double liters,
  String brand, {
  bool full = true,
  String fuelType = 'Normal',
  double? price,
}) =>
    FuelLog(
      vehicleId: kDefaultVehicleId,
      id: 'seed-$n',
      timestamp: '${date}T09:30:00.000',
      odometer: odometer,
      liters: liters,
      pumpBrand: brand,
      fullTank: full,
      fuelType: fuelType,
      pricePerLitre: price,
      totalCost: price != null
          ? double.parse((price * liters).toStringAsFixed(2))
          : null,
    );

/// Five months of driving: three brands, two fuel types, two partial fills,
/// and one fill without a price so the cost chart shows a gap.
final _seed = [
  _log(1, '2026-06-02', 12000, 32.0, 'Shell', price: 104.2),
  _log(2, '2026-06-16', 12560, 30.5, 'Indian Oil', price: 101.9),
  _log(3, '2026-06-24', 12850, 12.0, 'HP', full: false, price: 102.4),
  _log(4, '2026-07-05', 13160, 18.0, 'HP', price: 102.4),
  _log(5, '2026-07-21', 13690, 31.0, 'Shell',
      fuelType: 'XP-95', price: 111.5),
  _log(6, '2026-08-04', 14290, 29.0, 'Shell',
      fuelType: 'XP-95', price: 111.8),
  _log(7, '2026-08-19', 14820, 30.0, 'Indian Oil', price: 102.1),
  _log(8, '2026-08-30', 15100, 10.0, 'Indian Oil', full: false),
  _log(9, '2026-09-08', 15400, 21.0, 'HP', price: 102.6),
  _log(10, '2026-09-24', 16000, 30.5, 'Shell',
      fuelType: 'XP-95', price: 112.0),
  _log(11, '2026-10-07', 16540, 29.5, 'Indian Oil', price: 101.5),
  _log(12, '2026-10-16', 16880, 18.0, 'HP', full: false, price: 102.9),
  // A second vehicle, so the picker has something to switch to.
  _log(13, '2026-09-10', 4200, 5.0, 'Indian Oil', price: 101.8)
      .copyWith(vehicleId: _bike.id),
  _log(14, '2026-09-30', 4410, 4.8, 'HP', price: 102.6)
      .copyWith(vehicleId: _bike.id),
];

/// The default vehicle, renamed and given a tank, as a user would.
const _car = Vehicle(
    id: kDefaultVehicleId,
    name: 'Swift',
    tankCapacity: 37,
    createdAt: '2026-06-01T00:00:00.000');

const _bike = Vehicle(
    id: 'bike',
    name: 'Activa',
    type: VehicleType.bike,
    tankCapacity: 5.3,
    sortOrder: 1,
    createdAt: '2026-09-01T00:00:00.000');

Future<void> _loadFont(String family, List<String> paths) async {
  final loader = FontLoader(family);
  for (final p in paths) {
    final bytes = await File(p).readAsBytes();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

void main() {
  late ThemeData theme;
  late ThemeData light;

  setUpAll(() async {
    final fonts = join(Platform.environment['FLUTTER_ROOT']!, 'bin', 'cache',
        'artifacts', 'material_fonts');
    await _loadFont('Roboto', [
      join(fonts, 'roboto-regular.ttf'),
      join(fonts, 'roboto-medium.ttf'),
      join(fonts, 'roboto-bold.ttf'),
    ]);
    await _loadFont('MaterialIcons', [join(fonts, 'materialicons-regular.otf')]);
    await _loadFont('Segoe UI Emoji', [r'C:\Windows\Fonts\seguiemj.ttf']);

    final base = buildAppTheme(paletteById(kDefaultPaletteId), Brightness.dark);
    theme = base.copyWith(
      textTheme: base.textTheme.apply(
          fontFamily: 'Roboto', fontFamilyFallback: ['Segoe UI Emoji']),
      primaryTextTheme: base.primaryTextTheme.apply(
          fontFamily: 'Roboto', fontFamilyFallback: ['Segoe UI Emoji']),
    );

    final lb = buildAppTheme(paletteById(kDefaultPaletteId), Brightness.light);
    light = lb.copyWith(
      textTheme: lb.textTheme.apply(
          fontFamily: 'Roboto', fontFamilyFallback: ['Segoe UI Emoji']),
      primaryTextTheme: lb.primaryTextTheme.apply(
          fontFamily: 'Roboto', fontFamilyFallback: ['Segoe UI Emoji']),
    );

    // The analyzer only treats test/ as test code; this file is a test too.
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});

    // Isolated database: never the shared .dart_tool one other tests use.
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    await databaseFactory.setDatabasesPath(
        Directory.systemTemp.createTempSync('fuelpulse_shots_').path);
    final db = DatabaseHelper();
    await db.resetToDefaultVehicle();
    await db.updateVehicle(_car);
    await db.insertVehicle(_bike);
    await db.insertLogs(_seed);
    await db.upsertWorkshop(
        const Workshop(id: 'w1', name: 'City Motors', area: 'MG Road'));
    await db.insertService(const ServiceRecord(
        id: 's1',
        vehicleId: kDefaultVehicleId,
        timestamp: '2026-03-02T10:00:00.000',
        odometer: 10400,
        workshopId: 'w1',
        typeIds: ['air_filter'],
        cost: 650));
    await db.insertService(const ServiceRecord(
        id: 's2',
        vehicleId: kDefaultVehicleId,
        timestamp: '2026-07-10T10:00:00.000',
        odometer: 13500,
        workshopId: 'w1',
        typeIds: ['general', 'oil'],
        cost: 4200,
        nextDueKm: 18500,
        nextDueDate: '2027-01-10'));
  });

  Future<void> settle(WidgetTester tester) async {
    await tester
        .runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();
  }

  /// The app on [tab], optionally after tapping [tap], saved as [name].
  Future<void> capture(WidgetTester tester, String name,
      {int tab = 0, Finder? tap, bool dark = false}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    debugDisableShadows = false;
    try {
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? theme : light,
        home: const AppShell(),
      ));
      await settle(tester);
      if (tab > 0) {
        await tester.tap(find.byType(NavigationDestination).at(tab));
        await settle(tester);
      }
      if (tap != null) {
        await tester.ensureVisible(tap.first);
        await tester.pumpAndSettle();
        await tester.tap(tap.first);
        await settle(tester);
      }
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../screenshots/$name.png'),
      );
    } finally {
      debugDisableShadows = true;
    }
  }

  testWidgets('dashboard', (t) => capture(t, 'dashboard'));
  testWidgets('dashboard dark', (t) => capture(t, 'dashboard_dark', dark: true));
  testWidgets('fuel', (t) => capture(t, 'fuel', tab: 1));
  testWidgets('refill', (t) => capture(t, 'refill',
      tab: 1, tap: find.text('24 Sep · 16,000 km · 30.50 L')));
  testWidgets('add fill-up', (t) => capture(t, 'add_fill_up',
      tab: 1, tap: find.byTooltip('Add refill')));
  testWidgets('service', (t) => capture(t, 'service', tab: 2));
  testWidgets('analytics', (t) => capture(t, 'analytics', tab: 3));
  testWidgets('appearance', (t) => capture(t, 'appearance',
      tab: 4, tap: find.text('Colour palette'), dark: true));
}