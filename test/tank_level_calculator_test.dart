import 'package:flutter_test/flutter_test.dart';
import 'package:fuelpulse/models/fuel_log.dart';
import 'package:fuelpulse/models/vehicle.dart';
import 'package:fuelpulse/utils/efficiency_calculator.dart';
import 'package:fuelpulse/utils/tank_level_calculator.dart';

FuelLog _log(String id, int odometer, double liters, {bool full = true}) =>
    FuelLog(
      vehicleId: kDefaultVehicleId,
      id: id,
      timestamp: '2026-08-01T09:00:00.000',
      odometer: odometer,
      liters: liters,
      pumpBrand: 'Shell',
      fullTank: full,
    );

void main() {
  group('calculateTankLevels', () {
    test('empty input returns an empty map', () {
      expect(calculateTankLevels([], 40, {}), isEmpty);
    });

    test('full fill sets the level to tank capacity', () {
      final levels = calculateTankLevels([_log('a', 1000, 30)], 40, {});
      expect(levels['a'], 40);
    });

    test('full fill without a capacity uses the litres pumped', () {
      final levels = calculateTankLevels([_log('a', 1000, 30)], 0, {});
      expect(levels['a'], 30);
    });

    test('partial fill is clamped at tank capacity', () {
      final chrono = [
        _log('a', 1000, 30),
        _log('b', 1200, 15, full: false),
        _log('c', 1500, 15),
      ];
      // Segment a..c: 500 km on 30 L, so 16.67 km/L. Driving a to b uses
      // 12 L, leaving 28; adding 15 would give 43, over the 40 L tank.
      final levels =
          calculateTankLevels(chrono, 40, calculateEfficiency(chrono));
      expect(levels['a'], 40);
      expect(levels['b'], 40);
      expect(levels['c'], 40);
    });

    test('no consumption is subtracted before any efficiency is known', () {
      final chrono = [
        _log('a', 1000, 10, full: false),
        _log('b', 1200, 10, full: false),
      ];
      final levels = calculateTankLevels(chrono, 0, {});
      expect(levels['a'], 10);
      expect(levels['b'], 20);
    });

    test('consumption is clamped at zero before the next fill is added', () {
      final chrono = [
        _log('a', 1000, 30),
        _log('b', 2000, 10, full: false),
      ];
      // 1000 km at 5 km/L needs 200 L from a 30 L tank: the level bottoms
      // out at 0, then the partial fill adds 10.
      final levels = calculateTankLevels(
          chrono, 0, {'a': const EfficiencyResult(value: 5)});
      expect(levels['a'], 30);
      expect(levels['b'], 10);
    });
  });

  group('getFuelLevel', () {
    test('above 40 % is high', () {
      expect(getFuelLevel(16.4, 40), FuelLevel.high);
    });

    test('exactly 40 % is mid', () {
      expect(getFuelLevel(16, 40), FuelLevel.mid);
    });

    test('above 15 % is mid', () {
      expect(getFuelLevel(6.4, 40), FuelLevel.mid);
    });

    test('exactly 15 % is low', () {
      expect(getFuelLevel(6, 40), FuelLevel.low);
    });

    test('no capacity is mid', () {
      expect(getFuelLevel(10, 0), FuelLevel.mid);
    });
  });
}
