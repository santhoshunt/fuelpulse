import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fuelpulse/db/database_helper.dart';
import 'package:fuelpulse/models/fuel_log.dart';
import 'package:fuelpulse/models/vehicle.dart';
import 'package:fuelpulse/models/theme_preference.dart';
import 'package:fuelpulse/screens/home_screen.dart';
import 'package:fuelpulse/screens/stats_screen.dart';
import 'package:fuelpulse/utils/constants.dart';
import 'package:fuelpulse/widgets/trend_chart.dart';

final _db = DatabaseHelper();

const _myVehicle = Vehicle(
    id: kDefaultVehicleId, name: kDefaultVehicleName, createdAt: '');

FuelLog _log(
  String id,
  String date,
  int odometer,
  double liters, {
  bool full = true,
  double? price,
  String brand = 'Shell',
}) =>
    FuelLog(
      vehicleId: kDefaultVehicleId,
      id: id,
      timestamp: '${date}T09:00:00.000',
      odometer: odometer,
      liters: liters,
      pumpBrand: brand,
      fullTank: full,
      pricePerLitre: price,
    );

Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
  await tester.pumpAndSettle();
}

Future<void> _pumpScreen(WidgetTester tester, Widget screen) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: screen));
  await _settle(tester);
}

Future<void> _seed(WidgetTester tester, List<FuelLog> logs) async {
  await tester.runAsync(() => _db.insertLogs(logs));
}

Future<void> _scrollTo(WidgetTester tester, Finder f) async {
  await tester.scrollUntilVisible(f, 200);
  await tester.pumpAndSettle();
}

const _kmEmpty = 'Trend appears after 2 completed full-tank segments.';
const _costEmpty =
    'Add price or total to fill-ups to see cost per km over time.';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    await databaseFactory.setDatabasesPath(
        Directory.systemTemp.createTempSync('fuelpulse_stats_').path);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await _db.resetToDefaultVehicle();
  });

  group('StatsScreen', () {
    testWidgets('no logs shows the not-enough-data message', (tester) async {
      await _pumpScreen(tester, StatsScreen(vehicle: _myVehicle));
      expect(find.text('Not enough data'), findsOneWidget);
      expect(find.text('Trends'), findsNothing);
    });

    testWidgets('one segment shows both charts with their empty messages',
        (tester) async {
      await _seed(tester, [
        _log('a', '2026-06-01', 10000, 30),
        _log('b', '2026-06-15', 10500, 25),
      ]);
      await _pumpScreen(tester, StatsScreen(vehicle: _myVehicle));

      await _scrollTo(tester, find.text('Cost per km (₹)'));
      expect(find.text('Trends'), findsOneWidget);
      // Too few segments is the reason for both, so both say so.
      expect(find.text(_kmEmpty), findsNWidgets(2));
      expect(find.text(_costEmpty), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('several priced segments draw both charts', (tester) async {
      await _seed(tester, [
        _log('a', '2026-06-01', 10000, 30, price: 100),
        _log('b', '2026-06-15', 10500, 25, price: 101),
        _log('c', '2026-07-01', 11100, 30, price: 102),
        _log('d', '2026-07-20', 11650, 28, price: 103),
      ]);
      await _pumpScreen(tester, StatsScreen(vehicle: _myVehicle));

      await _scrollTo(tester, find.text('Cost per km (₹)'));
      expect(find.text(_kmEmpty), findsNothing);
      expect(find.text(_costEmpty), findsNothing);
      expect(
          find.descendant(
              of: find.byType(TrendChart), matching: find.byType(CustomPaint)),
          findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('segments without prices draw km/L but not cost',
        (tester) async {
      await _seed(tester, [
        _log('a', '2026-06-01', 10000, 30),
        _log('b', '2026-06-15', 10500, 25),
        _log('c', '2026-07-01', 11100, 30),
      ]);
      await _pumpScreen(tester, StatsScreen(vehicle: _myVehicle));

      await _scrollTo(tester, find.text(_costEmpty));
      expect(find.text(_kmEmpty), findsNothing);
      expect(find.text(_costEmpty), findsOneWidget);
    });

    testWidgets('cost data without a completed segment hides Trends',
        (tester) async {
      await _seed(tester, [_log('a', '2026-06-01', 10000, 30, price: 100)]);
      await _pumpScreen(tester, StatsScreen(vehicle: _myVehicle));
      expect(find.text('Cost Analytics'), findsOneWidget);
      expect(find.text('Trends'), findsNothing);
    });
  });

  group('TrendChart edge cases paint without errors', () {
    Future<void> pumpChart(WidgetTester tester, List<TrendPoint> points) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360,
            child: TrendChart(
              title: 'chart',
              points: points,
              formatValue: (v) => v.toStringAsFixed(1),
              emptyMessage: 'empty',
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    testWidgets('the average shows in the title row', (tester) async {
      await pumpChart(tester, [
        TrendPoint(DateTime(2026, 6, 1), 18),
        TrendPoint(DateTime(2026, 7, 1), 20),
      ]);
      expect(find.text('avg 19.0'), findsOneWidget);
    });

    test('month labels add the year only across a year boundary', () {
      expect(
          monthLabelFormat(DateTime(2026, 1, 5), DateTime(2026, 9, 1))
              .format(DateTime(2026, 6)),
          'Jun');
      expect(
          monthLabelFormat(DateTime(2025, 11, 5), DateTime(2026, 2, 1))
              .format(DateTime(2026, 1)),
          "Jan '26");
    });

    testWidgets('fewer than 2 points shows the empty message',
        (tester) async {
      await pumpChart(tester, [TrendPoint(DateTime(2026, 6, 1), 18)]);
      expect(find.text('empty'), findsOneWidget);
    });

    testWidgets('two points on the same date', (tester) async {
      await pumpChart(tester, [
        TrendPoint(DateTime(2026, 6, 1, 9), 18),
        TrendPoint(DateTime(2026, 6, 1, 9), 20),
      ]);
    });

    testWidgets('all values equal', (tester) async {
      await pumpChart(tester, [
        TrendPoint(DateTime(2026, 6, 1), 18),
        TrendPoint(DateTime(2026, 7, 1), 18),
        TrendPoint(DateTime(2026, 8, 1), 18),
      ]);
    });

    testWidgets('all values zero', (tester) async {
      await pumpChart(tester, [
        TrendPoint(DateTime(2026, 6, 1), 0),
        TrendPoint(DateTime(2026, 7, 1), 0),
      ]);
    });

    testWidgets('dates out of order', (tester) async {
      await pumpChart(tester, [
        TrendPoint(DateTime(2026, 9, 1), 18),
        TrendPoint(DateTime(2026, 6, 1), 20),
      ]);
    });

    testWidgets('a span of several years', (tester) async {
      await pumpChart(tester, [
        for (var y = 2018; y <= 2026; y++) TrendPoint(DateTime(y, 3, 1), 15.0 + y % 4),
      ]);
    });

    testWidgets('large and negative values', (tester) async {
      await pumpChart(tester, [
        TrendPoint(DateTime(2026, 6, 1), -50),
        TrendPoint(DateTime(2026, 6, 20), 125000),
      ]);
    });
  });

  group('HomeScreen', () {
    testWidgets('lists fill-ups and opens the add form', (tester) async {
      await _seed(tester, [
        _log('a', '2026-06-01', 10000, 30, brand: 'HP'),
        _log('b', '2026-06-15', 10500, 25, brand: 'Indian Oil'),
      ]);
      await _pumpScreen(tester,
          HomeScreen(theme: ThemePreference.defaults, onThemeChanged: (_) {}));

      expect(find.text('Indian Oil'), findsWidgets);
      await tester.tap(find.byType(FloatingActionButton));
      await _settle(tester);
      expect(find.text('Add Fill-up · My vehicle'), findsOneWidget);
    });
  });

  group('vehicles', () {
    const bike = Vehicle(
        id: 'bike',
        name: 'Activa',
        type: VehicleType.bike,
        sortOrder: 1,
        createdAt: '2026-06-01');

    Future<void> seedTwoVehicles(WidgetTester tester) async {
      await tester.runAsync(() async {
        await _db.insertVehicle(bike);
        await _db.insertLogs([
          _log('c1', '2026-06-01', 10000, 30, brand: 'HP'),
          _log('c2', '2026-06-15', 10500, 25, brand: 'HP'),
          _log('c3', '2026-07-01', 11000, 25, brand: 'HP'),
          _log('c4', '2026-07-15', 11500, 25, brand: 'HP'),
          _log('b1', '2026-06-10', 300, 4, brand: 'Shell')
              .copyWith(vehicleId: 'bike'),
          _log('b2', '2026-06-20', 520, 4, brand: 'Shell')
              .copyWith(vehicleId: 'bike'),
        ]);
      });
    }

    testWidgets('the chip switches Home to another vehicle', (tester) async {
      await seedTwoVehicles(tester);
      await _pumpScreen(tester,
          HomeScreen(theme: ThemePreference.defaults, onThemeChanged: (_) {}));

      expect(find.text(kDefaultVehicleName), findsOneWidget);
      expect(find.text('HP'), findsWidgets);
      expect(find.text('Shell'), findsNothing);

      await tester.tap(find.text(kDefaultVehicleName));
      await _settle(tester);
      await tester.tap(find.text('Activa'));
      await _settle(tester);

      expect(find.text('Activa'), findsOneWidget);
      expect(find.text('Shell'), findsWidgets);
      expect(find.text('HP'), findsNothing);
      final prefs = await tester.runAsync(SharedPreferences.getInstance);
      expect(prefs!.getString(kActiveVehicleKey), 'bike');
    });

    testWidgets('the add form names the active vehicle and saves to it',
        (tester) async {
      await seedTwoVehicles(tester);
      SharedPreferences.setMockInitialValues({kActiveVehicleKey: 'bike'});
      await _pumpScreen(tester,
          HomeScreen(theme: ThemePreference.defaults, onThemeChanged: (_) {}));

      await tester.tap(find.byType(FloatingActionButton));
      await _settle(tester);
      expect(find.text('Add Fill-up · Activa'), findsOneWidget);
    });

    testWidgets('Statistics reads only its own vehicle', (tester) async {
      await seedTwoVehicles(tester);
      await _pumpScreen(tester, const StatsScreen(vehicle: bike));

      expect(find.text('Statistics · Activa'), findsOneWidget);
      // The bike has one segment; the car's three must not leak in.
      await _scrollTo(tester, find.text('Cost per km (₹)'));
      expect(find.text(_kmEmpty), findsNWidgets(2));
      expect(find.text('HP'), findsNothing);
    });
  });
}
