import '../models/fuel_log.dart';

/// Result of efficiency calculation for a single log entry.
class EfficiencyResult {
  final double? value;
  final bool isPending;
  final double? segmentDistance;
  final double? segmentLiters;

  const EfficiencyResult({
    this.value,
    this.isPending = false,
    this.segmentDistance,
    this.segmentLiters,
  });

  static const pending = EfficiencyResult(isPending: true);
  static const none = EfficiencyResult();
}

/// Segment-based fuel efficiency calculation.
///
/// Input: chronologically sorted list (oldest first).
/// Output: map of log ID → EfficiencyResult.
///
/// A segment runs from one full-tank fill-up to the next.
/// Efficiency is attributed to entries segStart through i-1 (the fuel that
/// was actually consumed), NOT the closing fill-up whose fuel hasn't been used yet.
Map<String, EfficiencyResult> calculateEfficiency(List<FuelLog> chrono) {
  final results = <String, EfficiencyResult>{};

  if (chrono.isEmpty) return results;

  int segStart = -1;

  for (int i = 0; i < chrono.length; i++) {
    final entry = chrono[i];

    if (entry.fullTank) {
      if (segStart >= 0 && segStart != i) {
        final segDist = entry.odometer - chrono[segStart].odometer;
        double segLiters = 0;
        for (int j = segStart + 1; j <= i; j++) {
          segLiters += chrono[j].liters;
        }

        if (segDist > 0 && segLiters > 0) {
          final efficiency = segDist / segLiters;
          // Attribute to entries segStart through i-1: the fuel that was consumed.
          // Entry i (closing fill-up) starts the next segment — its fuel is unused.
          for (int j = segStart; j < i; j++) {
            results[chrono[j].id] = EfficiencyResult(
              value: efficiency,
              segmentDistance: segDist.toDouble(),
              segmentLiters: segLiters,
            );
          }
        }
      }
      segStart = i;
    }
  }

  // Mark unclosed segment entries as pending
  if (segStart >= 0) {
    for (int j = segStart; j < chrono.length; j++) {
      if (!results.containsKey(chrono[j].id)) {
        results[chrono[j].id] = EfficiencyResult.pending;
      }
    }
  }

  // Mark any remaining entries without a result
  for (final entry in chrono) {
    results.putIfAbsent(entry.id, () => EfficiencyResult.none);
  }

  return results;
}

/// Per-group efficiency data (a group is a brand, a fuel type, or any other
/// per-log string key).
class GroupEfficiency {
  final String label;
  final double weightedEfficiency;
  final double totalLiters;
  final int fillCount;
  final double deltaVsOverall;

  const GroupEfficiency({
    required this.label,
    required this.weightedEfficiency,
    required this.totalLiters,
    required this.fillCount,
    required this.deltaVsOverall,
  });
}

/// Grouped comparison result.
class GroupComparisonResult {
  final double overallEfficiency;
  final double totalKm;
  final double totalLiters;
  final List<GroupEfficiency> rankings; // sorted best → worst

  const GroupComparisonResult({
    required this.overallEfficiency,
    required this.totalKm,
    required this.totalLiters,
    required this.rankings,
  });
}

/// Per-brand efficiency data.
class BrandEfficiency {
  final String brand;
  final double weightedEfficiency;
  final double totalLiters;
  final int fillCount;
  final double deltaVsOverall;

  const BrandEfficiency({
    required this.brand,
    required this.weightedEfficiency,
    required this.totalLiters,
    required this.fillCount,
    required this.deltaVsOverall,
  });
}

/// Brand comparison result.
class BrandComparisonResult {
  final double overallEfficiency;
  final double totalKm;
  final double totalLiters;
  final List<BrandEfficiency> rankings; // sorted best → worst
  final String? bestBrand;
  final double? bestEfficiency;
  final String? worstBrand;
  final double? worstEfficiency;

  const BrandComparisonResult({
    required this.overallEfficiency,
    required this.totalKm,
    required this.totalLiters,
    required this.rankings,
    this.bestBrand,
    this.bestEfficiency,
    this.worstBrand,
    this.worstEfficiency,
  });
}

/// Calculate weighted average efficiency per group, where the group key of
/// each log is chosen by [keyOf] (pump brand, fuel type, ...).
///
/// Same segment algorithm as [calculateEfficiency], tracking per-group liters
/// within each segment. Attribution: the opening full-tank fill's group is
/// credited with the CLOSING fill's litres (the fuel consumed from its full
/// tank); partial fills in between are credited with their own litres.
/// Empty keys map to [emptyKeyLabel].
GroupComparisonResult calculateGroupedEfficiency(
  List<FuelLog> chrono,
  String Function(FuelLog) keyOf, {
  String emptyKeyLabel = 'Other',
}) {
  final effSum = <String, double>{};
  final litersSum = <String, double>{};
  final count = <String, int>{};
  double totalSegKm = 0;
  double totalSegLiters = 0;

  int segStart = -1;

  for (int i = 0; i < chrono.length; i++) {
    if (chrono[i].fullTank) {
      if (segStart >= 0 && segStart != i) {
        final segDist = chrono[i].odometer - chrono[segStart].odometer;
        double segLiters = 0;
        for (int j = segStart + 1; j <= i; j++) {
          segLiters += chrono[j].liters;
        }

        if (segDist > 0 && segLiters > 0) {
          final efficiency = segDist / segLiters;
          totalSegKm += segDist;
          totalSegLiters += segLiters;

          void credit(String rawKey, double liters) {
            final key = rawKey.isEmpty ? emptyKeyLabel : rawKey;
            if (liters > 0) {
              effSum[key] = (effSum[key] ?? 0) + efficiency * liters;
              litersSum[key] = (litersSum[key] ?? 0) + liters;
              count[key] = (count[key] ?? 0) + 1;
            }
          }

          // Opening entry: credited with closing liters (fuel consumed from
          // its full tank).
          credit(keyOf(chrono[segStart]), chrono[i].liters);
          // Partial fills between
          for (int j = segStart + 1; j < i; j++) {
            credit(keyOf(chrono[j]), chrono[j].liters);
          }
        }
      }
      segStart = i;
    }
  }

  final overallEff = totalSegLiters > 0 ? totalSegKm / totalSegLiters : 0.0;

  final rankings = <GroupEfficiency>[];
  for (final key in litersSum.keys) {
    final totalL = litersSum[key]!;
    final weightedEff = totalL > 0 ? effSum[key]! / totalL : 0.0;
    rankings.add(GroupEfficiency(
      label: key,
      weightedEfficiency: weightedEff,
      totalLiters: totalL,
      fillCount: count[key] ?? 0,
      deltaVsOverall: weightedEff - overallEff,
    ));
  }

  rankings.sort((a, b) => b.weightedEfficiency.compareTo(a.weightedEfficiency));

  return GroupComparisonResult(
    overallEfficiency: overallEff,
    totalKm: totalSegKm,
    totalLiters: totalSegLiters,
    rankings: rankings,
  );
}

/// Calculate per-brand weighted average efficiency.
BrandComparisonResult calculateBrandEfficiency(List<FuelLog> chrono) {
  final grouped = calculateGroupedEfficiency(chrono, (l) => l.pumpBrand);
  final rankings = grouped.rankings
      .map((g) => BrandEfficiency(
            brand: g.label,
            weightedEfficiency: g.weightedEfficiency,
            totalLiters: g.totalLiters,
            fillCount: g.fillCount,
            deltaVsOverall: g.deltaVsOverall,
          ))
      .toList();

  return BrandComparisonResult(
    overallEfficiency: grouped.overallEfficiency,
    totalKm: grouped.totalKm,
    totalLiters: grouped.totalLiters,
    rankings: rankings,
    bestBrand: rankings.isNotEmpty ? rankings.first.brand : null,
    bestEfficiency:
        rankings.isNotEmpty ? rankings.first.weightedEfficiency : null,
    worstBrand: rankings.length > 1 ? rankings.last.brand : null,
    worstEfficiency:
        rankings.length > 1 ? rankings.last.weightedEfficiency : null,
  );
}

/// Per-fuel-type efficiency plus the cost angle: does premium fuel pay for
/// itself?
class FuelTypeEfficiency {
  final String fuelType;
  final double weightedEfficiency;
  final double totalLiters; // segment-attributed litres
  final int fillCount;
  final double deltaVsOverall;

  /// Litre-weighted average price across ALL logs of this type that carry
  /// cost data. Null when none do.
  final double? avgPricePerLitre;

  /// avgPricePerLitre / weightedEfficiency (₹/L ÷ km/L = ₹/km).
  /// Null when either side is missing.
  final double? costPerKm;

  const FuelTypeEfficiency({
    required this.fuelType,
    required this.weightedEfficiency,
    required this.totalLiters,
    required this.fillCount,
    required this.deltaVsOverall,
    this.avgPricePerLitre,
    this.costPerKm,
  });
}

class FuelTypeComparisonResult {
  final double overallEfficiency;
  final List<FuelTypeEfficiency> rankings; // sorted best → worst

  const FuelTypeComparisonResult({
    required this.overallEfficiency,
    required this.rankings,
  });
}

/// Calculate per-fuel-type weighted efficiency and cost metrics.
///
/// Efficiency uses the segment attribution above. The price average is a
/// separate pass over ALL logs (price is a property of the purchase, not of
/// a consumption segment): per type, effective cost = totalCost when present,
/// else pricePerLitre × liters.
FuelTypeComparisonResult calculateFuelTypeEfficiency(List<FuelLog> chrono) {
  final grouped =
      calculateGroupedEfficiency(chrono, (l) => l.fuelType);

  final costSum = <String, double>{};
  final costLiters = <String, double>{};
  for (final log in chrono) {
    if (log.liters <= 0) continue;
    final cost = log.totalCost ??
        (log.pricePerLitre != null ? log.pricePerLitre! * log.liters : null);
    if (cost == null || cost <= 0) continue;
    costSum[log.fuelType] = (costSum[log.fuelType] ?? 0) + cost;
    costLiters[log.fuelType] = (costLiters[log.fuelType] ?? 0) + log.liters;
  }

  final rankings = grouped.rankings.map((g) {
    final litres = costLiters[g.label] ?? 0;
    final avgPrice = litres > 0 ? costSum[g.label]! / litres : null;
    final costPerKm = (avgPrice != null && g.weightedEfficiency > 0)
        ? avgPrice / g.weightedEfficiency
        : null;
    return FuelTypeEfficiency(
      fuelType: g.label,
      weightedEfficiency: g.weightedEfficiency,
      totalLiters: g.totalLiters,
      fillCount: g.fillCount,
      deltaVsOverall: g.deltaVsOverall,
      avgPricePerLitre: avgPrice,
      costPerKm: costPerKm,
    );
  }).toList();

  return FuelTypeComparisonResult(
    overallEfficiency: grouped.overallEfficiency,
    rankings: rankings,
  );
}
