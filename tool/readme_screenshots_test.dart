// Renders the README screenshots offscreen. A generator, not a test: it lives
// outside test/ so `flutter test` (and CI) never runs it, and it reads fonts
// from this Windows machine. Run it by hand:
//
//   flutter test tool/readme_screenshots_test.dart --update-goldens
//
// Output: screenshots/home.png, add_fill_up.png, stats.png, stats_trends.png.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' show join;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fuelpulse/db/database_helper.dart';
import 'package:fuelpulse/models/fuel_log.dart';
import 'package:fuelpulse/models/vehicle.dart';
import 'package:fuelpulse/models/theme_preference.dart';
import 'package:fuelpulse/screens/entry_form_screen.dart';
import 'package:fuelpulse/screens/home_screen.dart';
import 'package:fuelpulse/screens/stats_screen.dart';
import 'package:fuelpulse/utils/theme_manager.dart' as tm;

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

    final base = tm.buildThemeData(ThemePreference.defaults);
    theme = base.copyWith(
      textTheme: base.textTheme.apply(
          fontFamily: 'Roboto', fontFamilyFallback: ['Segoe UI Emoji']),
      primaryTextTheme: base.primaryTextTheme.apply(
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
  });

  Future<void> capture(
    WidgetTester tester,
    Widget screen,
    String name, {
    Future<void> Function()? before,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    debugDisableShadows = false;
    try {
      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: screen,
      ));
      await tester
          .runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle();
      if (before != null) await before();
      await expectLater(
        find.byType(MaterialApp),
        matchesGoldenFile('../screenshots/$name.png'),
      );
    } finally {
      debugDisableShadows = true;
    }
  }

  testWidgets('home', (tester) async {
    await capture(
      tester,
      HomeScreen(theme: ThemePreference.defaults, onThemeChanged: (_) {}),
      'home',
    );
  });

  testWidgets('vehicle picker', (tester) async {
    await capture(
      tester,
      HomeScreen(theme: ThemePreference.defaults, onThemeChanged: (_) {}),
      'vehicles',
      before: () async {
        await tester.tap(find.text('Swift'));
        await tester.runAsync(
            () => Future.delayed(const Duration(milliseconds: 100)));
        await tester.pumpAndSettle();
      },
    );
  });

  testWidgets('add fill-up', (tester) async {
    await capture(tester, const EntryFormScreen(vehicleId: kDefaultVehicleId),
        'add_fill_up');
  });

  testWidgets('stats', (tester) async {
    await capture(tester, const StatsScreen(vehicle: _car), 'stats');
  });

  testWidgets('stats trends', (tester) async {
    await capture(tester, const StatsScreen(vehicle: _car), 'stats_trends',
        before: () async {
      await tester.ensureVisible(find.text('Trends'));
      await tester.pumpAndSettle();
    });
  });
}
