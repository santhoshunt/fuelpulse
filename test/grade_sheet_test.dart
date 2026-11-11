import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fuelpulse/models/fuel_log.dart';
import 'package:fuelpulse/models/vehicle.dart';
import 'package:fuelpulse/widgets/grade_sheet.dart';

// Swiping the fill-up sheet up opens the fill-up page; a short drag does not.
void main() {
  const vehicle = Vehicle(id: 'v', name: 'Swift', createdAt: '2026-01-01');
  final log = FuelLog(
    vehicleId: 'v',
    id: 'f1',
    timestamp: '2026-09-24T09:30:00.000',
    odometer: 16000,
    liters: 30.5,
    pumpBrand: 'Shell',
    fuelType: 'XP-95',
  );

  Future<List<GradeAction?>> open(WidgetTester tester) async {
    final results = <GradeAction?>[];
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: TextButton(
            onPressed: () async =>
                results.add(await showGradeSheet(ctx, log: log, vehicle: vehicle)),
            child: const Text('open sheet'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('a swipe up opens the fill-up', (tester) async {
    final results = await open(tester);
    expect(find.text('Swipe up for the full fill-up'), findsOneWidget);
    await tester.drag(find.text('Swipe up for the full fill-up'),
        const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(results, [GradeAction.open]);
  });

  testWidgets('a short drag up leaves the sheet open', (tester) async {
    final results = await open(tester);
    await tester.drag(find.text('Swipe up for the full fill-up'),
        const Offset(0, -40));
    await tester.pumpAndSettle();
    expect(results, isEmpty);
    expect(find.text('Open fill-up'), findsOneWidget);
  });
}
