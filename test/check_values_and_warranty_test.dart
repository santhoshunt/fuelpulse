import 'package:flutter_test/flutter_test.dart';

import 'package:fuelpulse/models/check.dart';
import 'package:fuelpulse/models/fuel_log.dart';
import 'package:fuelpulse/models/part.dart';
import 'package:fuelpulse/screens/part_form_screen.dart' show warrantyLine;

Part _battery(String? until) => Part(
      id: 'p1',
      vehicleId: 'v',
      kind: 'battery',
      label: 'Battery',
      fittedAt: '2025-03-12',
      fittedOdometer: 1000,
      warrantyUntil: until,
    );

void main() {
  test('a check keeps its unit and values through the database map', () {
    const c = Check(
      id: 'q1',
      vehicleId: 'v',
      name: 'Tyre pressure',
      everyDays: 14,
      lastDoneAt: '2026-11-15T09:00:00.000',
      unit: 'psi',
      history: [(at: '2026-11-15T09:00:00.000', value: '32')],
    );
    final back = Check.fromMap(c.toMap());
    expect(back.unit, 'psi');
    expect(back.history, c.history);
    expect(back.withUnit('32'), '32 psi');
  });

  test('a check from before 4.5 has no unit and no values', () {
    final c = Check.fromMap({
      'id': 'q1',
      'vehicleId': 'v',
      'name': 'Chain lube',
      'everyKm': 500,
      'lastDoneAt': '2026-11-01T09:00:00.000',
      'lastDoneKm': 1000,
    });
    expect(c.unit, '');
    expect(c.history, isEmpty);
    expect(c.withUnit('OK'), 'OK');
  });

  test('a fill-up keeps its road, and an unknown one reads as none', () {
    final log = FuelLog(
        vehicleId: 'v',
        id: '1',
        timestamp: '2026-11-01T09:00:00.000',
        odometer: 1000,
        liters: 10,
        pumpBrand: 'Shell',
        road: 'highway');
    expect(FuelLog.fromMap(log.toMap()).road, 'highway');
    expect(FuelLog.fromMap({...log.toMap(), 'road': 'offroad'}).road, isNull);
    expect(log.copyWith(clearRoad: true).road, isNull);
  });

  group('warranty line', () {
    final now = DateTime(2026, 11, 15, 20);

    test('none without a date or once it ended', () {
      expect(warrantyLine(_battery(null), now), isNull);
      expect(warrantyLine(_battery('2026-11-14'), now), isNull);
    });

    test('the date when more than 30 days away', () {
      expect(warrantyLine(_battery('2027-03-12'), now),
          (text: 'Warranty until 12 Mar 2027', soon: false));
    });

    test('the days left in the last 30', () {
      expect(warrantyLine(_battery('2026-12-05'), now),
          (text: 'Warranty ends in 20 days, 5 Dec', soon: true));
      expect(warrantyLine(_battery('2026-11-16'), now),
          (text: 'Warranty ends tomorrow, 16 Nov', soon: true));
      expect(warrantyLine(_battery('2026-11-15'), now),
          (text: 'Warranty ends today', soon: true));
    });
  });
}
