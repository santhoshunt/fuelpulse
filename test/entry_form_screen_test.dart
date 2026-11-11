import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:fuelpulse/db/database_helper.dart';
import 'package:fuelpulse/models/fuel_log.dart';
import 'package:fuelpulse/models/vehicle.dart';
import 'package:fuelpulse/screens/entry_form_screen.dart';
import 'package:fuelpulse/widgets/mode_switch.dart';

final _db = DatabaseHelper();

FuelLog _log(
  String id,
  int odometer, {
  String timestamp = '2026-08-01T09:00:00.000',
  double liters = 30,
  String brand = 'HP',
  String fuelType = 'Normal',
  bool full = true,
  double? totalCost,
  double? pricePerLitre,
}) =>
    FuelLog(
      vehicleId: kDefaultVehicleId,
      id: id,
      timestamp: timestamp,
      odometer: odometer,
      liters: liters,
      pumpBrand: brand,
      fuelType: fuelType,
      fullTank: full,
      totalCost: totalCost,
      pricePerLitre: pricePerLitre,
    );

/// Real sqflite work completes outside the fake clock, so give it a moment
/// of real time before settling the widget tree.
Future<void> _settle(WidgetTester tester) async {
  await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
  await tester.pumpAndSettle();
}

Future<T> _real<T>(WidgetTester tester, Future<T> Function() fn) async =>
    (await tester.runAsync(fn)) as T;

/// Opens the form from a launcher route so the form's Navigator.pop has
/// somewhere to return to. The returned list collects pop results.
Future<List<Object?>> _openForm(WidgetTester tester, {String? logId}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);

  final results = <Object?>[];
  await tester.pumpWidget(MaterialApp(
    home: Builder(
      builder: (ctx) => Scaffold(
        body: TextButton(
          onPressed: () async {
            results.add(await Navigator.push(
              ctx,
              MaterialPageRoute(
                  builder: (_) => EntryFormScreen(
                      logId: logId,
                      vehicleId: logId == null ? kDefaultVehicleId : null)),
            ));
          },
          child: const Text('open form'),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open form'));
  await _settle(tester);
  return results;
}

Finder _field(String label) => find.widgetWithText(TextFormField, label);

String _text(WidgetTester tester, String label) =>
    tester.widget<TextFormField>(_field(label)).controller!.text;

Future<void> _tapButton(WidgetTester tester, String label) async {
  final f = find.widgetWithText(ElevatedButton, label);
  await tester.ensureVisible(f);
  await tester.tap(f);
  await _settle(tester);
}

/// A segment of the Odometer or Distance switch, not the field below it.
Finder _modeSegment(String label) =>
    find.descendant(of: find.byType(ModeSwitch), matching: find.text(label));

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    // Own database file: other test files share the default one.
    await databaseFactory.setDatabasesPath(
        Directory.systemTemp.createTempSync('fuelpulse_form_').path);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await _db.resetToDefaultVehicle();
  });

  group('leaving the form', () {
    Future<void> back(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await _settle(tester);
    }

    testWidgets('Back with nothing typed closes without asking',
        (tester) async {
      final results = await _openForm(tester);
      await back(tester);
      expect(find.text('Discard changes?'), findsNothing);
      expect(results, [null]);
    });

    testWidgets('Back after typing asks, and Keep editing stays',
        (tester) async {
      final results = await _openForm(tester);
      await tester.enterText(_field('Litres'), '20');
      await back(tester);
      expect(find.text('Discard changes?'), findsOneWidget);

      await tester.tap(find.text('Keep editing'));
      await _settle(tester);
      expect(results, isEmpty);
      expect(_text(tester, 'Litres'), '20');

      await back(tester);
      await tester.tap(find.text('Discard'));
      await _settle(tester);
      expect(results, [null]);
    });

    testWidgets('an opened fill-up left as it was closes without asking',
        (tester) async {
      await _real(tester, () => _db.insertLogs([_log('a', 10000)]));
      final results = await _openForm(tester, logId: 'a');
      await back(tester);
      expect(find.text('Discard changes?'), findsNothing);
      expect(results, [null]);
    });
  });

  group('add mode', () {
    testWidgets('saves a new fill-up and derives the total from the price',
        (tester) async {
      final results = await _openForm(tester);
      expect(find.text('Add fill-up · My vehicle'), findsOneWidget);

      await tester.enterText(_field('Odometer'), '12000');
      await tester.enterText(_field('Litres'), '20');
      await tester.enterText(_field('Price (₹/L)'), '100');
      expect(_text(tester, 'Total (₹)'), '2000.00');

      await _tapButton(tester, 'Save fill-up');

      expect(results, [true]);
      final logs = await _real(tester, () => _db.getAllLogs(kDefaultVehicleId));
      expect(logs, hasLength(1));
      final log = logs.single;
      expect(log.odometer, 12000);
      expect(log.liters, 20);
      expect(log.pricePerLitre, 100);
      expect(log.totalCost, 2000);
      expect(log.fullTank, isTrue);
      expect(log.fuelType, 'Normal');
      expect(log.pumpBrand, 'Shell');
      expect(DateTime.tryParse(log.timestamp), isNotNull);
    });

    testWidgets('typing the total derives the price, and litres edits keep '
        'the total fixed', (tester) async {
      await _openForm(tester);
      await tester.enterText(_field('Litres'), '20');
      await tester.enterText(_field('Total (₹)'), '2000');
      expect(_text(tester, 'Price (₹/L)'), '100.00');

      await tester.enterText(_field('Litres'), '25');
      expect(_text(tester, 'Total (₹)'), '2000');
      expect(_text(tester, 'Price (₹/L)'), '80.00');
    });

    testWidgets('clearing the price clears the derived total',
        (tester) async {
      await _openForm(tester);
      await tester.enterText(_field('Litres'), '20');
      await tester.enterText(_field('Price (₹/L)'), '100');
      await tester.enterText(_field('Price (₹/L)'), '');
      expect(_text(tester, 'Total (₹)'), '');
    });

    testWidgets('empty required fields block the save', (tester) async {
      final results = await _openForm(tester);
      await _tapButton(tester, 'Save fill-up');

      expect(find.text('Enter the odometer reading'), findsOneWidget);
      expect(find.text('Enter the litres'), findsOneWidget);
      expect(results, isEmpty);
      expect(await _real(tester, _db.getLogCount), 0);
    });

    testWidgets('KM mode is disabled when there are no logs', (tester) async {
      await _openForm(tester);
      await tester.tap(find.text('Distance'));
      await _settle(tester);
      expect(_field('Odometer'), findsOneWidget);
      expect(_field('Distance since last fill-up'), findsNothing);
    });

    testWidgets('a negative KM distance is refused', (tester) async {
      await _real(tester, () => _db.insertLog(_log('prev', 10000)));
      final results = await _openForm(tester);

      await tester.tap(find.text('Distance'));
      await _settle(tester);
      await tester.enterText(_field('Distance since last fill-up'), '-200');
      await tester.enterText(_field('Litres'), '20');
      await _tapButton(tester, 'Save fill-up');

      expect(find.text("Distance can't be negative"), findsOneWidget);
      expect(results, isEmpty);
      expect(await _real(tester, _db.getLogCount), 1);
    });

    testWidgets('KM mode ignores another vehicle\'s later fill-up',
        (tester) async {
      await _real(tester, () async {
        await _db.insertVehicle(const Vehicle(
            id: 'bike', name: 'Activa', createdAt: '2026-01-01'));
        await _db.insertLog(_log('car', 10000,
            timestamp: '2026-07-01T09:00:00.000'));
        await _db.insertLog(_log('bike-later', 500,
                timestamp: '2026-07-20T09:00:00.000')
            .copyWith(vehicleId: 'bike'));
      });
      await _openForm(tester);

      await tester.tap(find.text('Distance'));
      await _settle(tester);
      expect(find.text('Last fill-up at 10000 km'), findsOneWidget);
    });

    testWidgets('KM mode adds the distance to the latest odometer',
        (tester) async {
      await _real(tester, () => _db.insertLog(_log('prev', 10000)));
      await _openForm(tester);

      await tester.tap(find.text('Distance'));
      await _settle(tester);
      expect(find.text('Last fill-up at 10000 km'), findsOneWidget);

      await tester.enterText(_field('Distance since last fill-up'), '450');
      await tester.enterText(_field('Litres'), '25');
      await _tapButton(tester, 'Save fill-up');

      final logs = await _real(tester, () => _db.getAllLogsChrono(kDefaultVehicleId));
      expect(logs.map((l) => l.odometer), [10000, 10450]);
    });

    testWidgets('switching modes converts a typed reading both ways',
        (tester) async {
      await _real(tester, () => _db.insertLog(_log('prev', 10000)));
      await _openForm(tester);

      await tester.enterText(_field('Odometer'), '10400');
      await tester.tap(find.text('Distance'));
      await _settle(tester);
      expect(_text(tester, 'Distance since last fill-up'), '400');

      await tester.tap(_modeSegment('Odometer'));
      await _settle(tester);
      expect(_text(tester, 'Odometer'), '10400');
    });

    testWidgets('tapping the mode that is already selected changes nothing',
        (tester) async {
      await _real(tester, () => _db.insertLog(_log('prev', 10000)));
      await _openForm(tester);

      await tester.enterText(_field('Odometer'), '10400');
      await tester.tap(_modeSegment('Odometer'));
      await _settle(tester);
      expect(_text(tester, 'Odometer'), '10400');

      await tester.tap(find.text('Distance'));
      await _settle(tester);
      await tester.tap(find.text('Distance'));
      await _settle(tester);
      expect(_text(tester, 'Distance since last fill-up'), '400');
    });

    testWidgets('a backward odometer asks first, and Cancel saves nothing',
        (tester) async {
      await _real(tester, () => _db.insertLog(_log('prev', 10000)));
      final results = await _openForm(tester);

      await tester.enterText(_field('Odometer'), '9000');
      await tester.enterText(_field('Litres'), '25');
      await _tapButton(tester, 'Save fill-up');
      expect(find.text('Odometer looks wrong'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await _settle(tester);
      expect(results, isEmpty);
      expect(await _real(tester, _db.getLogCount), 1);

      await _tapButton(tester, 'Save fill-up');
      await tester.tap(find.text('Save anyway'));
      await _settle(tester);
      expect(results, [true]);
      expect(await _real(tester, _db.getLogCount), 2);
    });

    testWidgets('Full Tank off saves a partial fill', (tester) async {
      await _openForm(tester);
      await tester.enterText(_field('Odometer'), '12000');
      await tester.enterText(_field('Litres'), '10');
      await tester.tap(find.byType(Switch));
      await _settle(tester);
      await _tapButton(tester, 'Save fill-up');

      final log = (await _real(tester, () => _db.getAllLogs(kDefaultVehicleId))).single;
      expect(log.fullTank, isFalse);
    });
  });

  group('edit mode', () {
    testWidgets('prefills the form from the log', (tester) async {
      await _real(
          tester,
          () => _db.insertLog(_log('a', 10000,
              liters: 22.5,
              brand: 'Indian Oil',
              fuelType: 'XP-95',
              totalCost: 2500,
              pricePerLitre: 111.11)));
      await _openForm(tester, logId: 'a');

      expect(find.text('Edit fill-up · My vehicle'), findsOneWidget);
      expect(_text(tester, 'Odometer'), '10000');
      expect(_text(tester, 'Litres'), '22.5');
      expect(_text(tester, 'Price (₹/L)'), '111.11');
      expect(_text(tester, 'Total (₹)'), '2500.0');
      expect(find.text('Indian Oil'), findsOneWidget);
      expect(find.text('XP-95'), findsOneWidget);
    });

    testWidgets('saves after confirmation and keeps id and timestamp',
        (tester) async {
      await _real(
          tester,
          () => _db.insertLog(
              _log('a', 10000, timestamp: '2026-07-01T08:15:00.000')));
      final results = await _openForm(tester, logId: 'a');

      await tester.enterText(_field('Litres'), '28');
      await tester.enterText(_field('Notes (optional)'), 'highway');
      await _tapButton(tester, 'Save changes');
      expect(find.text('Save the changes to this fill-up?'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await _settle(tester);

      expect(results, [true]);
      final log = (await _real(tester, () => _db.getAllLogs(kDefaultVehicleId))).single;
      expect(log.id, 'a');
      expect(log.timestamp, '2026-07-01T08:15:00.000');
      expect(log.liters, 28);
      expect(log.notes, 'highway');
    });

    testWidgets('Cancel on the confirmation leaves the log unchanged',
        (tester) async {
      await _real(tester, () => _db.insertLog(_log('a', 10000)));
      final results = await _openForm(tester, logId: 'a');

      await tester.enterText(_field('Litres'), '28');
      await _tapButton(tester, 'Save changes');
      await tester.tap(find.text('Cancel'));
      await _settle(tester);

      expect(results, isEmpty);
      final log = (await _real(tester, () => _db.getAllLogs(kDefaultVehicleId))).single;
      expect(log.liters, 30);
    });

    testWidgets('clearing both cost fields saves them as empty',
        (tester) async {
      await _real(
          tester,
          () => _db.insertLog(
              _log('a', 10000, totalCost: 3000, pricePerLitre: 100)));
      await _openForm(tester, logId: 'a');

      await tester.enterText(_field('Total (₹)'), '');
      expect(_text(tester, 'Price (₹/L)'), '');
      await _tapButton(tester, 'Save changes');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await _settle(tester);

      final log = (await _real(tester, () => _db.getAllLogs(kDefaultVehicleId))).single;
      expect(log.totalCost, isNull);
      expect(log.pricePerLitre, isNull);
    });

    testWidgets('KM mode counts from the previous log, not the latest',
        (tester) async {
      await _real(
          tester,
          () => _db.insertLogs([
                _log('a', 10000, timestamp: '2026-07-01T09:00:00.000'),
                _log('b', 10600, timestamp: '2026-07-10T09:00:00.000'),
                _log('c', 11200, timestamp: '2026-07-20T09:00:00.000'),
              ]));
      await _openForm(tester, logId: 'b');

      await tester.tap(find.text('Distance'));
      await _settle(tester);
      expect(_text(tester, 'Distance since last fill-up'), '600');
      expect(find.text('Fill-up before this one at 10000 km'), findsOneWidget);

      await tester.enterText(_field('Distance since last fill-up'), '700');
      await _tapButton(tester, 'Save changes');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await _settle(tester);

      final logs = await _real(tester, () => _db.getAllLogsChrono(kDefaultVehicleId));
      expect(logs.map((l) => l.odometer), [10000, 10700, 11200]);
    });

    testWidgets('KM mode is disabled for the first log', (tester) async {
      await _real(
          tester,
          () => _db.insertLogs([
                _log('a', 10000, timestamp: '2026-07-01T09:00:00.000'),
                _log('b', 10600, timestamp: '2026-07-10T09:00:00.000'),
              ]));
      await _openForm(tester, logId: 'a');
      await tester.tap(find.text('Distance'));
      await _settle(tester);
      expect(_field('Distance since last fill-up'), findsNothing);
    });

    testWidgets('a fuel type and brand missing from the lists are kept',
        (tester) async {
      await _real(
          tester,
          () => _db.insertLog(
              _log('a', 10000, brand: 'Reliance', fuelType: 'Diesel+')));
      await _openForm(tester, logId: 'a');
      expect(find.text('Reliance'), findsOneWidget);
      expect(find.text('Diesel+'), findsOneWidget);

      await _tapButton(tester, 'Save changes');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Save'));
      await _settle(tester);

      final log = (await _real(tester, () => _db.getAllLogs(kDefaultVehicleId))).single;
      expect(log.pumpBrand, 'Reliance');
      expect(log.fuelType, 'Diesel+');
    });

    testWidgets('a missing log closes the form', (tester) async {
      await _openForm(tester, logId: 'does-not-exist');
      expect(find.text('open form'), findsOneWidget);
      expect(find.textContaining('Edit fill-up'), findsNothing);
    });
  });
}
