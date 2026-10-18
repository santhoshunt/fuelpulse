import 'package:flutter_test/flutter_test.dart';
import 'package:fuelpulse/models/fuel_log.dart';
import 'package:fuelpulse/utils/trend_calculator.dart';

FuelLog _log(
  String id,
  String timestamp,
  int odometer,
  double liters, {
  bool full = true,
  double? totalCost,
  double? pricePerLitre,
}) =>
    FuelLog(
      id: id,
      timestamp: timestamp,
      odometer: odometer,
      liters: liters,
      pumpBrand: 'Shell',
      fullTank: full,
      totalCost: totalCost,
      pricePerLitre: pricePerLitre,
    );

void main() {
  test('empty input returns no points', () {
    expect(calculateSegmentTrend([]), isEmpty);
  });

  test('a single full fill returns no points', () {
    expect(
        calculateSegmentTrend([_log('a', '2026-06-01T09:00:00', 1000, 30)]),
        isEmpty);
  });

  test('two full fills give one point dated at the closing fill', () {
    final points = calculateSegmentTrend([
      _log('a', '2026-06-01T09:00:00', 1000, 30),
      _log('b', '2026-06-15T09:00:00', 1500, 25),
    ]);
    expect(points, hasLength(1));
    expect(points.single.kmPerLitre, 20.0);
    expect(points.single.closedAt, DateTime(2026, 6, 15, 9));
    expect(points.single.costPerKm, isNull);
  });

  test('a partial fill inside the segment adds its litres', () {
    final points = calculateSegmentTrend([
      _log('a', '2026-06-01T09:00:00', 1000, 30),
      _log('b', '2026-06-08T09:00:00', 1200, 10, full: false),
      _log('c', '2026-06-15T09:00:00', 1500, 15),
    ]);
    expect(points.single.kmPerLitre, 20.0);
  });

  test('cost per km is set when every closing-litre fill has cost data', () {
    final points = calculateSegmentTrend([
      // The opening fill's cost belongs to the previous segment.
      _log('a', '2026-06-01T09:00:00', 1000, 30),
      _log('b', '2026-06-08T09:00:00', 1200, 10,
          full: false, totalCost: 1000),
      _log('c', '2026-06-15T09:00:00', 1500, 15, pricePerLitre: 100),
    ]);
    // 1000 + 15 x 100 = 2500 over 500 km.
    expect(points.single.costPerKm, 5.0);
  });

  test('cost per km is null when one closing-litre fill lacks cost data', () {
    final points = calculateSegmentTrend([
      _log('a', '2026-06-01T09:00:00', 1000, 30, totalCost: 3000),
      _log('b', '2026-06-08T09:00:00', 1200, 10, full: false),
      _log('c', '2026-06-15T09:00:00', 1500, 15, pricePerLitre: 100),
    ]);
    expect(points.single.kmPerLitre, 20.0);
    expect(points.single.costPerKm, isNull);
  });

  test('a segment with no forward distance is skipped', () {
    final points = calculateSegmentTrend([
      _log('a', '2026-06-01T09:00:00', 1000, 30),
      _log('b', '2026-06-15T09:00:00', 1000, 25),
      _log('c', '2026-06-29T09:00:00', 1500, 25),
    ]);
    expect(points, hasLength(1));
    expect(points.single.closedAt, DateTime(2026, 6, 29, 9));
  });

  test('a closing timestamp that does not parse is skipped', () {
    final points = calculateSegmentTrend([
      _log('a', '2026-06-01T09:00:00', 1000, 30),
      _log('b', 'not a date', 1500, 25),
      _log('c', '2026-06-29T09:00:00', 2000, 25),
    ]);
    expect(points, hasLength(1));
    expect(points.single.closedAt, DateTime(2026, 6, 29, 9));
  });
}
