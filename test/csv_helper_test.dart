import 'package:flutter_test/flutter_test.dart';
import 'package:fuelpulse/models/fuel_log.dart';
import 'package:fuelpulse/models/vehicle.dart';
import 'package:fuelpulse/utils/csv_helper.dart';

void main() {
  test('build → parse round-trip carries fuel type and costs', () {
    final logs = [
      FuelLog(
        vehicleId: kDefaultVehicleId,
        id: 'a',
        timestamp: '2026-08-01T09:00:00.000',
        odometer: 1000,
        liters: 10.5,
        pumpBrand: 'Indian Oil',
        fuelType: 'XP-95',
        totalCost: 1150.0,
        pricePerLitre: 109.52,
        notes: 'first',
      ),
      FuelLog(
        vehicleId: kDefaultVehicleId,
        id: 'b',
        timestamp: '2026-08-10T09:00:00.000',
        odometer: 1400,
        liters: 8.0,
        pumpBrand: 'Shell',
        fullTank: false,
      ),
    ];

    final parsed = parseCsvRows(buildCsvRows(logs), vehicleId: 'bike');
    expect(parsed.length, 2);
    // CSV carries no vehicle: every row lands in the one importing.
    expect(parsed.map((l) => l.vehicleId), ['bike', 'bike']);
    expect(parsed[0].fuelType, 'XP-95');
    expect(parsed[0].totalCost, 1150.0);
    expect(parsed[0].pricePerLitre, 109.52);
    expect(parsed[0].fullTank, isTrue);
    expect(parsed[1].fuelType, 'Normal'); // empty column → default
    expect(parsed[1].totalCost, isNull);
    expect(parsed[1].pricePerLitre, isNull);
    expect(parsed[1].fullTank, isFalse);
    // CSV import regenerates IDs by design (Drive restore honors them).
    expect(parsed[0].id, isNot('a'));
  });

  test('legacy 7-column CSV still imports', () {
    final rows = <List<dynamic>>[
      ['id', 'timestamp', 'odometer', 'liters', 'pumpBrand', 'fullTank', 'notes'],
      ['x', '2025-01-01T00:00:00.000', 5000, 20.0, 'HP', 'true', 'old'],
    ];
    final parsed = parseCsvRows(rows, vehicleId: kDefaultVehicleId);
    expect(parsed.single.odometer, 5000);
    expect(parsed.single.fuelType, 'Normal');
    expect(parsed.single.totalCost, isNull);
  });

  test('claimed columns are not double-matched', () {
    // "totalcost" resolves before the price aliases, and a claimed index is
    // skipped — so "total price" (matching alias "price") goes to the price
    // slot while "totalcost" keeps the total slot.
    final rows = <List<dynamic>>[
      ['odometer', 'liters', 'totalcost', 'total price'],
      [1000, 10.0, 950.0, 95.0],
    ];
    final parsed = parseCsvRows(rows, vehicleId: kDefaultVehicleId);
    expect(parsed.single.totalCost, 950.0);
    expect(parsed.single.pricePerLitre, 95.0);
  });

  test('missing required columns throw', () {
    expect(
      () => parseCsvRows([
        ['timestamp', 'brand'],
        ['2025-01-01', 'Shell'],
      ], vehicleId: kDefaultVehicleId),
      throwsFormatException,
    );
  });
}
