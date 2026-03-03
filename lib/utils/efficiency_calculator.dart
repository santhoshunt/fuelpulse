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

/// Calculate per-brand weighted average efficiency.
///
/// Uses the same segment algorithm, but tracks per-brand liters within each segment.
BrandComparisonResult calculateBrandEfficiency(List<FuelLog> chrono) {
  final brandEffSum = <String, double>{};
  final brandLitersSum = <String, double>{};
  final brandCount = <String, int>{};
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

          // Credit brands whose fuel was consumed: segStart through i-1.
          // segStart's brand gets chrono[i].liters (the amount consumed from its full tank).
          // Partial fills (segStart+1..i-1) get their own liters.
          void creditBrand(String rawBrand, double liters) {
            final brand = rawBrand.isEmpty ? 'Other' : rawBrand;
            if (liters > 0) {
              brandEffSum[brand] =
                  (brandEffSum[brand] ?? 0) + efficiency * liters;
              brandLitersSum[brand] =
                  (brandLitersSum[brand] ?? 0) + liters;
              brandCount[brand] = (brandCount[brand] ?? 0) + 1;
            }
          }
          // Opening entry's brand: credited with closing liters (fuel consumed from full tank)
          creditBrand(chrono[segStart].pumpBrand, chrono[i].liters);
          // Partial fills between
          for (int j = segStart + 1; j < i; j++) {
            creditBrand(chrono[j].pumpBrand, chrono[j].liters);
          }
        }
      }
      segStart = i;
    }
  }

  final overallEff = totalSegLiters > 0 ? totalSegKm / totalSegLiters : 0.0;

  final rankings = <BrandEfficiency>[];
  for (final brand in brandLitersSum.keys) {
    final totalL = brandLitersSum[brand]!;
    final weightedEff = totalL > 0 ? brandEffSum[brand]! / totalL : 0.0;
    rankings.add(BrandEfficiency(
      brand: brand,
      weightedEfficiency: weightedEff,
      totalLiters: totalL,
      fillCount: brandCount[brand] ?? 0,
      deltaVsOverall: weightedEff - overallEff,
    ));
  }

  rankings.sort((a, b) => b.weightedEfficiency.compareTo(a.weightedEfficiency));

  return BrandComparisonResult(
    overallEfficiency: overallEff,
    totalKm: totalSegKm,
    totalLiters: totalSegLiters,
    rankings: rankings,
    bestBrand: rankings.isNotEmpty ? rankings.first.brand : null,
    bestEfficiency:
        rankings.isNotEmpty ? rankings.first.weightedEfficiency : null,
    worstBrand:
        rankings.length > 1 ? rankings.last.brand : null,
    worstEfficiency:
        rankings.length > 1 ? rankings.last.weightedEfficiency : null,
  );
}
