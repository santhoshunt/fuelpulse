import 'package:flutter/material.dart';

import '../models/vehicle.dart';

/// Five mileage bands (Poor, Low, Fair, Good, Great) split by four
/// ascending km/L limits. A value equal to a limit falls in the band above.
class MileageBands {
  final List<double> limits;

  const MileageBands(this.limits);

  static const names = ['Poor', 'Low', 'Fair', 'Good', 'Great'];

  /// 0 (Poor) to 4 (Great).
  int bandIndex(double kmL) {
    var i = 0;
    while (i < limits.length && kmL >= limits[i]) {
      i++;
    }
    return i;
  }
}

/// Five cost bands split by four descending ₹/km limits: cheaper per km is
/// better, so a cost above the first limit is Poor and below the last Great.
class CostBands {
  final List<double> limits;

  const CostBands(this.limits);

  /// 0 (Poor) to 4 (Great). A cost equal to a limit counts as the better band.
  int bandIndex(double perKm) {
    var i = 0;
    while (i < limits.length && perKm <= limits[i]) {
      i++;
    }
    return i;
  }
}

/// Typical ₹/km at 2026 prices: a bike at 30 to 40 km/L, a car at 12 to 18.
CostBands defaultCostBandsFor(VehicleType t) => t == VehicleType.bike
    ? const CostBands([5, 4, 3.5, 3])
    : const CostBands([10, 8, 7, 6]);

CostBands costBandsFor(Vehicle v) => v.costBands != null
    ? CostBands(v.costBands!)
    : defaultCostBandsFor(v.type);

/// A fill-up's grade from both measures: the lower of its km/L band and,
/// when it has a price, its ₹/km band.
({int grade, int mileage, int? cost, double? perKm}) gradeOf(
    Vehicle v, double kmL, double? pricePerLitre) {
  final m = bandsFor(v).bandIndex(kmL);
  final perKm =
      pricePerLitre != null && kmL > 0 ? pricePerLitre / kmL : null;
  final c = perKm == null ? null : costBandsFor(v).bandIndex(perKm);
  return (grade: c == null || m < c ? m : c, mileage: m, cost: c, perKm: perKm);
}

/// The vehicle's own bands, else the defaults for its type.
MileageBands bandsFor(Vehicle v) => v.mileageBands != null
    ? MileageBands(v.mileageBands!)
    : defaultBandsFor(v.type);

/// Typical ranges: a commuter bike runs about three times a car's km/L.
MileageBands defaultBandsFor(VehicleType t) => t == VehicleType.bike
    ? const MileageBands([20, 25, 28, 32])
    : const MileageBands([10, 13, 16, 19]);

const _light = [
  Color(0xFFB3261E),
  Color(0xFFC2410C),
  Color(0xFF8A6D00),
  Color(0xFF4F7A16),
  Color(0xFF1E7A46),
];
const _dark = [
  Color(0xFFF2867F),
  Color(0xFFF59E5B),
  Color(0xFFE6C34A),
  Color(0xFF9CCB5E),
  Color(0xFF5FD08F),
];

/// Red to green, readable as text on the card colour of either mode.
Color bandColor(int index, Brightness b) =>
    (b == Brightness.dark ? _dark : _light)[index.clamp(0, 4)];
