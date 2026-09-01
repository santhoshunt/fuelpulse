import 'package:flutter_test/flutter_test.dart';
import 'package:fuelpulse/models/fuel_log.dart';
import 'package:fuelpulse/utils/cost_calculator.dart';

FuelLog _log({
  required String id,
  required int odometer,
  double liters = 10,
  String timestamp = '2026-08-01T09:00:00.000',
  double? totalCost,
  double? pricePerLitre,
}) =>
    FuelLog(
      id: id,
      timestamp: timestamp,
      odometer: odometer,
      liters: liters,
      pumpBrand: 'Shell',
      totalCost: totalCost,
      pricePerLitre: pricePerLitre,
    );

void main() {
  group('computeTotalCost / computePricePerLitre', () {
    test('happy path', () {
      expect(computeTotalCost(100, 10), 1000);
      expect(computePricePerLitre(1000, 10), 100);
    });

    test('null, zero, and negative inputs return null', () {
      expect(computeTotalCost(null, 10), isNull);
      expect(computeTotalCost(100, null), isNull);
      expect(computeTotalCost(100, 0), isNull);
      expect(computeTotalCost(-5, 10), isNull);
      expect(computePricePerLitre(1000, 0), isNull);
      expect(computePricePerLitre(0, 10), isNull);
      expect(computePricePerLitre(double.nan, 10), isNull);
    });
  });

  group('formatMoney', () {
    test('trims trailing zeros', () {
      expect(formatMoney(2500), '2500');
      expect(formatMoney(104.5), '104.5');
      expect(formatMoney(104.55), '104.55');
      expect(formatMoney(104.999), '105');
    });
  });

  group('calculateCostStats', () {
    test('empty list → zeros and nulls', () {
      final s = calculateCostStats([]);
      expect(s.totalSpend, 0);
      expect(s.avgPricePerLitre, isNull);
      expect(s.costPerKm, isNull);
      expect(s.monthSpend, 0);
      expect(s.avgMonthlySpend, isNull);
      expect(s.costLogCount, 0);
    });

    test('logs without cost contribute nothing', () {
      final s = calculateCostStats([
        _log(id: '1', odometer: 1000),
        _log(id: '2', odometer: 1500),
      ]);
      expect(s.totalSpend, 0);
      expect(s.costLogCount, 0);
    });

    test('effective total is derived from price × litres when total absent',
        () {
      final s = calculateCostStats([
        _log(id: '1', odometer: 1000, liters: 10, pricePerLitre: 100),
      ]);
      expect(s.totalSpend, 1000);
      expect(s.costLogCount, 1);
      expect(s.avgPricePerLitre, 100);
    });

    test('costPerKm uses odometer span across ALL logs', () {
      final now = DateTime(2026, 8, 15);
      final s = calculateCostStats([
        _log(
            id: '1',
            odometer: 1000,
            liters: 10,
            totalCost: 1000,
            timestamp: '2026-07-01T09:00:00.000'),
        _log(id: '2', odometer: 1500, timestamp: '2026-08-01T09:00:00.000'),
        _log(
            id: '3',
            odometer: 2000,
            liters: 10,
            totalCost: 1000,
            timestamp: '2026-08-10T09:00:00.000'),
      ], now: now);
      expect(s.totalSpend, 2000);
      expect(s.costPerKm, 2000 / 1000);
      // Month bucketing with a fixed `now` — only the Aug 10 fill counts.
      expect(s.monthSpend, 1000);
      // Two distinct months with cost data → avg 1000/month.
      expect(s.avgMonthlySpend, 1000);
    });

    test('costPerKm null when odometer span is zero', () {
      final s = calculateCostStats([
        _log(id: '1', odometer: 1000, totalCost: 500),
      ]);
      expect(s.costPerKm, isNull);
      expect(s.totalSpend, 500);
    });
  });
}
