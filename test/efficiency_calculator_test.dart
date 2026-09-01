import 'package:flutter_test/flutter_test.dart';
import 'package:fuelpulse/models/fuel_log.dart';
import 'package:fuelpulse/utils/efficiency_calculator.dart';

FuelLog _log({
  required String id,
  required int odometer,
  double liters = 10,
  String brand = 'Shell',
  String fuelType = 'Normal',
  bool fullTank = true,
  double? totalCost,
  double? pricePerLitre,
}) =>
    FuelLog(
      id: id,
      timestamp: '2026-08-01T09:00:00.000',
      odometer: odometer,
      liters: liters,
      pumpBrand: brand,
      fullTank: fullTank,
      fuelType: fuelType,
      totalCost: totalCost,
      pricePerLitre: pricePerLitre,
    );

void main() {
  group('calculateBrandEfficiency (parity regression across refactor)', () {
    test('opening brand credited with closing litres, partial with its own',
        () {
      // Segment: full(Shell, odo 1000) -> partial(HP, 5L) -> full(Shell, 10L, odo 1300)
      // segDist = 300, segLiters = 15, eff = 20 km/L
      // Shell (opening) credited with the CLOSING 10L; HP with its own 5L.
      final chrono = [
        _log(id: '1', odometer: 1000, brand: 'Shell'),
        _log(id: '2', odometer: 1150, brand: 'HP', liters: 5, fullTank: false),
        _log(id: '3', odometer: 1300, brand: 'Shell', liters: 10),
      ];

      final r = calculateBrandEfficiency(chrono);
      expect(r.overallEfficiency, closeTo(20.0, 1e-9));
      expect(r.totalKm, 300);
      expect(r.totalLiters, 15);
      expect(r.rankings.length, 2);

      final shell = r.rankings.singleWhere((b) => b.brand == 'Shell');
      final hp = r.rankings.singleWhere((b) => b.brand == 'HP');
      expect(shell.totalLiters, 10);
      expect(shell.fillCount, 1);
      expect(shell.weightedEfficiency, closeTo(20.0, 1e-9));
      expect(hp.totalLiters, 5);
      expect(hp.weightedEfficiency, closeTo(20.0, 1e-9));

      expect(r.bestBrand, isNotNull);
      expect(r.worstBrand, isNotNull); // two brands -> worst is set
    });

    test('weighted average across segments and delta signs', () {
      // Seg 1: Shell full -> Shell full, 200 km / 10 L = 20 km/L
      // Seg 2: Shell full -> HP full, 100 km / 10 L = 10 km/L
      //   (Shell opening credited with HP's closing 10 L at 10 km/L)
      final chrono = [
        _log(id: '1', odometer: 1000, brand: 'Shell'),
        _log(id: '2', odometer: 1200, brand: 'Shell', liters: 10),
        _log(id: '3', odometer: 1300, brand: 'HP', liters: 10),
      ];

      final r = calculateBrandEfficiency(chrono);
      // Overall: 300 km / 20 L = 15 km/L
      expect(r.overallEfficiency, closeTo(15.0, 1e-9));
      final shell = r.rankings.singleWhere((b) => b.brand == 'Shell');
      // Shell: (20*10 + 10*10) / 20 = 15
      expect(shell.weightedEfficiency, closeTo(15.0, 1e-9));
      expect(shell.deltaVsOverall, closeTo(0.0, 1e-9));
      // HP got no credit (its fill only CLOSED a segment).
      expect(r.rankings.any((b) => b.brand == 'HP'), isFalse);
    });

    test('single brand yields no worst', () {
      final chrono = [
        _log(id: '1', odometer: 1000),
        _log(id: '2', odometer: 1200),
      ];
      final r = calculateBrandEfficiency(chrono);
      expect(r.rankings.length, 1);
      expect(r.bestBrand, 'Shell');
      expect(r.worstBrand, isNull);
    });
  });

  group('calculateGroupedEfficiency', () {
    test('groups by an arbitrary key and maps empty keys', () {
      final chrono = [
        _log(id: '1', odometer: 1000, brand: ''),
        _log(id: '2', odometer: 1200, brand: 'HP', liters: 10),
      ];
      final r = calculateGroupedEfficiency(chrono, (l) => l.pumpBrand,
          emptyKeyLabel: 'Unknown');
      expect(r.rankings.single.label, 'Unknown');
      expect(r.rankings.single.totalLiters, 10);
    });

    test('empty input yields empty result', () {
      final r = calculateGroupedEfficiency([], (l) => l.pumpBrand);
      expect(r.rankings, isEmpty);
      expect(r.overallEfficiency, 0);
    });

    test('no closed segment yields empty rankings', () {
      final chrono = [
        _log(id: '1', odometer: 1000, fullTank: false),
        _log(id: '2', odometer: 1200, fullTank: false),
      ];
      final r = calculateGroupedEfficiency(chrono, (l) => l.pumpBrand);
      expect(r.rankings, isEmpty);
    });
  });

  group('calculateFuelTypeEfficiency', () {
    test('ranks fuel types by weighted efficiency with deltas', () {
      // Seg 1 (XP-95): 220 km / 10 L = 22 km/L
      // Seg 2 (Normal): 180 km / 10 L = 18 km/L
      final chrono = [
        _log(id: '1', odometer: 1000, fuelType: 'XP-95'),
        _log(id: '2', odometer: 1220, fuelType: 'Normal', liters: 10),
        _log(id: '3', odometer: 1400, fuelType: 'XP-95', liters: 10),
      ];
      // Attribution: XP-95 opens seg 1 -> credited 10 L at 22 km/L.
      // Normal opens seg 2 -> credited 10 L at 18 km/L.
      final r = calculateFuelTypeEfficiency(chrono);
      expect(r.rankings.length, 2);
      expect(r.rankings.first.fuelType, 'XP-95');
      expect(r.rankings.first.weightedEfficiency, closeTo(22.0, 1e-9));
      expect(r.rankings.last.fuelType, 'Normal');
      expect(r.rankings.last.weightedEfficiency, closeTo(18.0, 1e-9));
      // Overall: 400 km / 20 L = 20 km/L
      expect(r.overallEfficiency, closeTo(20.0, 1e-9));
      expect(r.rankings.first.deltaVsOverall, closeTo(2.0, 1e-9));
      expect(r.rankings.last.deltaVsOverall, closeTo(-2.0, 1e-9));
    });

    test('litre-weighted avg price ignores no-cost logs, costPerKm derives',
        () {
      final chrono = [
        // XP-95 with price data: 10 L at 110/L and 10 L via totalCost 1000
        _log(id: '1', odometer: 1000, fuelType: 'XP-95', pricePerLitre: 110),
        _log(
            id: '2',
            odometer: 1200,
            fuelType: 'XP-95',
            liters: 10,
            totalCost: 1000),
        // no-cost XP-95 log: must not drag the average
        _log(id: '3', odometer: 1400, fuelType: 'XP-95', liters: 10),
        // Normal with no cost data; the trailing XP-95 fill closes Normal's
        // segment so it earns a ranking entry.
        _log(id: '4', odometer: 1600, fuelType: 'Normal', liters: 10),
        _log(id: '5', odometer: 1800, fuelType: 'XP-95', liters: 10),
      ];
      final r = calculateFuelTypeEfficiency(chrono);
      final xp = r.rankings.singleWhere((f) => f.fuelType == 'XP-95');
      final normal = r.rankings.singleWhere((f) => f.fuelType == 'Normal');

      // Avg price: (110*10 + 1000) / 20 = 105
      expect(xp.avgPricePerLitre, closeTo(105.0, 1e-9));
      // Efficiency: each segment 200 km / 10 L = 20 km/L for every opener.
      expect(xp.weightedEfficiency, closeTo(20.0, 1e-9));
      expect(xp.costPerKm, closeTo(105.0 / 20.0, 1e-9));

      expect(normal.avgPricePerLitre, isNull);
      expect(normal.costPerKm, isNull);
    });

    test('single fuel type still ranks (UI gates on >= 2)', () {
      final chrono = [
        _log(id: '1', odometer: 1000),
        _log(id: '2', odometer: 1200),
      ];
      final r = calculateFuelTypeEfficiency(chrono);
      expect(r.rankings.length, 1);
      expect(r.rankings.single.fuelType, 'Normal');
    });

    test('empty input yields empty rankings', () {
      final r = calculateFuelTypeEfficiency([]);
      expect(r.rankings, isEmpty);
    });
  });
}
