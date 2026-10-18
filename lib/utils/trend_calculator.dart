import '../models/fuel_log.dart';
import 'cost_calculator.dart';

/// One completed full-tank segment, as plotted on the Statistics trends.
class SegmentTrendPoint {
  /// Parsed timestamp of the full fill that closed the segment.
  final DateTime closedAt;

  /// Segment distance divided by the litres pumped to close it.
  final double kmPerLitre;

  /// Segment spend divided by segment distance, in rupees per km. Null
  /// unless every fill whose litres count toward the segment has cost data.
  final double? costPerKm;

  const SegmentTrendPoint({
    required this.closedAt,
    required this.kmPerLitre,
    this.costPerKm,
  });
}

/// One point per completed full-tank segment, oldest first.
///
/// Same segment rules as [calculateEfficiency]: a segment closes at the next
/// full fill, its litres are the fills after the opening one up to and
/// including the closing one, and it counts only when distance and litres
/// are both positive. A segment whose closing timestamp does not parse is
/// skipped, since it cannot be placed on a time axis.
///
/// Spend uses the same entries as the litres, with each log's effective cost
/// taken the way [calculateCostStats] takes it. Counting only the priced
/// fills would understate a segment's cost, so one unpriced fill leaves
/// [SegmentTrendPoint.costPerKm] null for that segment.
List<SegmentTrendPoint> calculateSegmentTrend(List<FuelLog> chrono) {
  final points = <SegmentTrendPoint>[];
  int segStart = -1;

  for (int i = 0; i < chrono.length; i++) {
    if (!chrono[i].fullTank) continue;

    if (segStart >= 0 && segStart != i) {
      final segDist = chrono[i].odometer - chrono[segStart].odometer;
      double segLiters = 0;
      double? segSpend = 0;
      for (int j = segStart + 1; j <= i; j++) {
        final log = chrono[j];
        segLiters += log.liters;
        final cost =
            log.totalCost ?? computeTotalCost(log.pricePerLitre, log.liters);
        segSpend = (cost == null || segSpend == null) ? null : segSpend + cost;
      }

      final closedAt = DateTime.tryParse(chrono[i].timestamp);
      if (segDist > 0 && segLiters > 0 && closedAt != null) {
        points.add(SegmentTrendPoint(
          closedAt: closedAt,
          kmPerLitre: segDist / segLiters,
          costPerKm: segSpend != null ? segSpend / segDist : null,
        ));
      }
    }
    segStart = i;
  }

  return points;
}
