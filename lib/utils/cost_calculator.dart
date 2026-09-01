import '../models/fuel_log.dart';

/// Total cost from rate and litres. Null when either input is unusable.
double? computeTotalCost(double? pricePerLitre, double? liters) {
  if (pricePerLitre == null || liters == null) return null;
  if (!pricePerLitre.isFinite || !liters.isFinite) return null;
  if (pricePerLitre <= 0 || liters <= 0) return null;
  return pricePerLitre * liters;
}

/// Rate from total cost and litres. Null when either input is unusable.
double? computePricePerLitre(double? totalCost, double? liters) {
  if (totalCost == null || liters == null) return null;
  if (!totalCost.isFinite || !liters.isFinite) return null;
  if (totalCost <= 0 || liters <= 0) return null;
  return totalCost / liters;
}

/// Display formatting: 2 decimals with trailing zeros trimmed ("104.5", "2500").
String formatMoney(double v) {
  var s = v.toStringAsFixed(2);
  if (s.contains('.')) {
    s = s.replaceFirst(RegExp(r'\.?0+$'), '');
  }
  return s;
}

class CostStats {
  /// Sum of effective totals across all logs that have cost data.
  final double totalSpend;

  /// Litre-weighted average price per litre. Null when no cost data.
  final double? avgPricePerLitre;

  /// totalSpend divided by the odometer span across ALL logs.
  /// Null when the span is zero or there is no spend.
  final double? costPerKm;

  /// Spend in the current calendar month.
  final double monthSpend;

  /// totalSpend divided by the number of distinct months with cost data.
  final double? avgMonthlySpend;

  /// How many logs carry cost data (for "N of M fill-ups" subtitles).
  final int costLogCount;

  const CostStats({
    required this.totalSpend,
    required this.avgPricePerLitre,
    required this.costPerKm,
    required this.monthSpend,
    required this.avgMonthlySpend,
    required this.costLogCount,
  });
}

/// Cost analytics over chronologically ordered logs. A log's effective total
/// is its stored totalCost, else pricePerLitre x liters when both exist.
CostStats calculateCostStats(List<FuelLog> chrono, {DateTime? now}) {
  final current = now ?? DateTime.now();

  double totalSpend = 0;
  double litersWithCost = 0;
  double spendWithLiters = 0;
  double monthSpend = 0;
  int costLogCount = 0;
  final months = <String>{};

  for (final log in chrono) {
    final effective =
        log.totalCost ?? computeTotalCost(log.pricePerLitre, log.liters);
    if (effective == null) continue;

    costLogCount++;
    totalSpend += effective;
    if (log.liters > 0) {
      litersWithCost += log.liters;
      spendWithLiters += effective;
    }

    final ts = DateTime.tryParse(log.timestamp);
    if (ts != null) {
      months.add('${ts.year}-${ts.month}');
      if (ts.year == current.year && ts.month == current.month) {
        monthSpend += effective;
      }
    }
  }

  double? avgPrice;
  if (litersWithCost > 0) {
    avgPrice = spendWithLiters / litersWithCost;
  }

  double? costPerKm;
  if (totalSpend > 0 && chrono.length >= 2) {
    final minOdo = chrono.map((l) => l.odometer).reduce((a, b) => a < b ? a : b);
    final maxOdo = chrono.map((l) => l.odometer).reduce((a, b) => a > b ? a : b);
    final span = maxOdo - minOdo;
    if (span > 0) costPerKm = totalSpend / span;
  }

  return CostStats(
    totalSpend: totalSpend,
    avgPricePerLitre: avgPrice,
    costPerKm: costPerKm,
    monthSpend: monthSpend,
    avgMonthlySpend: months.isEmpty ? null : totalSpend / months.length,
    costLogCount: costLogCount,
  );
}
