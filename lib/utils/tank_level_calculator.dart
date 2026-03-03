import '../models/fuel_log.dart';
import 'efficiency_calculator.dart';

/// Estimate tank level for each entry using a forward-walk model.
///
/// Input: chronological list (oldest first), tank capacity, efficiency map.
/// Output: map of log ID → estimated tank level in liters.
Map<String, double> calculateTankLevels(
  List<FuelLog> chrono,
  double tankCapacity,
  Map<String, EfficiencyResult> efficiencyMap,
) {
  final levels = <String, double>{};
  if (chrono.isEmpty) return levels;

  double level = 0;
  double lastEfficiency = 0;
  final hasCap = tankCapacity > 0;

  for (int i = 0; i < chrono.length; i++) {
    final entry = chrono[i];

    // Consume fuel based on distance since previous entry
    if (i > 0) {
      final dist = entry.odometer - chrono[i - 1].odometer;
      if (lastEfficiency > 0 && dist > 0) {
        level = (level - dist / lastEfficiency).clamp(0, double.infinity);
      }
    }

    // Add fuel
    if (entry.fullTank) {
      level = hasCap ? tankCapacity : entry.liters;
    } else {
      if (hasCap) {
        level = (level + entry.liters).clamp(0, tankCapacity);
      } else {
        level = level + entry.liters;
      }
    }

    levels[entry.id] = level;

    // Update last known efficiency
    final eff = efficiencyMap[entry.id];
    if (eff != null && eff.value != null && eff.value! > 0) {
      lastEfficiency = eff.value!;
    }
  }

  return levels;
}

/// Determine fuel gauge color tier.
enum FuelLevel { high, mid, low }

FuelLevel getFuelLevel(double level, double capacity) {
  if (capacity <= 0) return FuelLevel.mid;
  final pct = level / capacity;
  if (pct > 0.4) return FuelLevel.high;
  if (pct > 0.15) return FuelLevel.mid;
  return FuelLevel.low;
}
