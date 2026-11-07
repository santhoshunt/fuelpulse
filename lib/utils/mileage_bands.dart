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
