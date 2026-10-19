import 'package:flutter_test/flutter_test.dart';
import 'package:fuelpulse/models/fuel_log.dart';
import 'package:fuelpulse/models/vehicle.dart';
import 'package:fuelpulse/utils/efficiency_calculator.dart';

void main() {
  group('FuelLog', () {
    test('generateId returns unique IDs', () {
      final id1 = FuelLog.generateId();
      final id2 = FuelLog.generateId();
      expect(id1, isNot(equals(id2)));
    });

    test('toMap and fromMap round-trip', () {
      final log = FuelLog(
        vehicleId: kDefaultVehicleId,
        id: 'test-1',
        timestamp: '2025-01-01T00:00:00.000Z',
        odometer: 10000,
        liters: 30.5,
        pumpBrand: 'Shell',
        fullTank: true,
        notes: 'Test note',
      );
      final map = log.toMap();
      final restored = FuelLog.fromMap(map);

      expect(restored.id, log.id);
      expect(restored.odometer, log.odometer);
      expect(restored.liters, log.liters);
      expect(restored.pumpBrand, log.pumpBrand);
      expect(restored.fullTank, log.fullTank);
      expect(restored.notes, log.notes);
    });

    test('round-trip with fuel type and cost fields', () {
      final log = FuelLog(
        vehicleId: kDefaultVehicleId,
        id: 'test-2',
        timestamp: '2026-08-01T00:00:00.000Z',
        odometer: 12000,
        liters: 23.92,
        pumpBrand: 'Indian Oil',
        fuelType: 'XP-95',
        totalCost: 2500.0,
        pricePerLitre: 104.5,
      );
      final restored = FuelLog.fromMap(log.toMap());
      expect(restored.fuelType, 'XP-95');
      expect(restored.totalCost, 2500.0);
      expect(restored.pricePerLitre, 104.5);
    });

    test('legacy map (no new keys) defaults to Normal and null costs', () {
      final restored = FuelLog.fromMap({
        'id': 'legacy-1',
        'timestamp': '2025-01-01T00:00:00.000Z',
        'odometer': 5000,
        'liters': 20.0,
        'pumpBrand': 'HP',
        'fullTank': 1,
        'notes': '',
      });
      expect(restored.fuelType, 'Normal');
      expect(restored.totalCost, isNull);
      expect(restored.pricePerLitre, isNull);
    });

    test('fromMap tolerates a JSON double odometer', () {
      final restored = FuelLog.fromMap({
        'id': 'json-1',
        'timestamp': '2025-01-01T00:00:00.000Z',
        'odometer': 5000.0,
        'liters': 20.0,
      });
      expect(restored.odometer, 5000);
    });

    test('copyWith clear flags actually clear cost fields', () {
      final log = FuelLog(
        vehicleId: kDefaultVehicleId,
        id: 'test-3',
        timestamp: '2026-08-01T00:00:00.000Z',
        odometer: 100,
        liters: 10,
        pumpBrand: 'Shell',
        totalCost: 999.0,
        pricePerLitre: 99.9,
      );
      final kept = log.copyWith(odometer: 200);
      expect(kept.totalCost, 999.0);
      expect(kept.pricePerLitre, 99.9);

      final cleared =
          log.copyWith(clearTotalCost: true, clearPricePerLitre: true);
      expect(cleared.totalCost, isNull);
      expect(cleared.pricePerLitre, isNull);
    });
  });

  group('EfficiencyCalculator', () {
    test('returns empty map for empty input', () {
      expect(calculateEfficiency([]), isEmpty);
    });

    test('single entry is pending', () {
      final logs = [
        FuelLog(
          vehicleId: kDefaultVehicleId,
          id: '1', timestamp: '2025-01-01T00:00:00Z',
          odometer: 1000, liters: 30, pumpBrand: 'Shell', fullTank: true,
        ),
      ];
      final result = calculateEfficiency(logs);
      expect(result['1']?.isPending, true);
    });

    test('two full-tank entries produce correct efficiency', () {
      final logs = [
        FuelLog(
          vehicleId: kDefaultVehicleId,
          id: '1', timestamp: '2025-01-01T00:00:00Z',
          odometer: 1000, liters: 30, pumpBrand: 'Shell', fullTank: true,
        ),
        FuelLog(
          vehicleId: kDefaultVehicleId,
          id: '2', timestamp: '2025-01-02T00:00:00Z',
          odometer: 1500, liters: 25, pumpBrand: 'HP', fullTank: true,
        ),
      ];
      final result = calculateEfficiency(logs);
      // segDist = 500, segLiters = 25, efficiency = 20.0
      // Attributed to entry 1 (Shell — its fuel was consumed), not entry 2
      expect(result['1']?.value, 20.0);
      expect(result['2']?.isPending, true); // just filled, fuel not consumed yet
    });

    test('partial fill included in segment', () {
      final logs = [
        FuelLog(
          vehicleId: kDefaultVehicleId,
          id: '1', timestamp: '2025-01-01T00:00:00Z',
          odometer: 1000, liters: 30, pumpBrand: 'Shell', fullTank: true,
        ),
        FuelLog(
          vehicleId: kDefaultVehicleId,
          id: '2', timestamp: '2025-01-02T00:00:00Z',
          odometer: 1200, liters: 10, pumpBrand: 'HP', fullTank: false,
        ),
        FuelLog(
          vehicleId: kDefaultVehicleId,
          id: '3', timestamp: '2025-01-03T00:00:00Z',
          odometer: 1500, liters: 15, pumpBrand: 'Shell', fullTank: true,
        ),
      ];
      final result = calculateEfficiency(logs);
      // segDist = 500, segLiters = 10 + 15 = 25, efficiency = 20.0
      // Attributed to entries 1 and 2 (fuel consumed), not entry 3
      expect(result['1']?.value, 20.0);  // Shell — full tank consumed
      expect(result['2']?.value, 20.0);  // HP — partial fill consumed
      expect(result['3']?.isPending, true); // Shell — just filled, fuel unused
    });
  });
}
