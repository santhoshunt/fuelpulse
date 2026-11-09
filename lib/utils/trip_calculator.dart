import 'dart:math' as math;

import '../models/fuel_log.dart';
import '../models/trip.dart';
import 'cost_calculator.dart';
import 'efficiency_calculator.dart';

/// The vehicle's overall km/L over its closed full-tank stretches, or null.
double? averageKmL(List<FuelLog> chrono) {
  final o = calculateBrandEfficiency(chrono);
  return o.totalLiters > 0 ? o.overallEfficiency : null;
}

/// How sure a trip's fuel figure is.
/// - estimate: some km use the vehicle's average, because the full-tank
///   stretch they fall in hasn't closed yet.
/// - measured: every km falls in a closed full-tank stretch.
/// - exact: measured, and the trip started and ended on full fill-ups.
enum FuelQuality { estimate, measured, exact }

/// A run of the trip charged at one km/L.
class TripPiece {
  final int fromKm, toKm;
  final double kmPerLitre;

  /// False when [kmPerLitre] is the vehicle's average.
  final bool closed;

  const TripPiece(this.fromKm, this.toKm, this.kmPerLitre, this.closed);

  double get litres => (toKm - fromKm) / kmPerLitre;
}

class TripFuel {
  final double litres;
  final FuelQuality quality;
  final List<TripPiece> pieces;

  /// Rupees, from [pricePerLitre]; null without any price.
  final double? cost;
  final double? pricePerLitre;

  const TripFuel({
    required this.litres,
    required this.quality,
    required this.pieces,
    this.cost,
    this.pricePerLitre,
  });

  int get km => pieces.isEmpty ? 0 : pieces.last.toKm - pieces.first.fromKm;
  double? get kmPerLitre => litres > 0 ? km / litres : null;
}

/// The fuel [trip] used between its start odometer and [endOdometer] (the
/// end reading, or the latest reading for a trip still on). Each km is
/// charged at the km/L of the closed full-tank stretch it falls in: from
/// one full fill-up to the next, distance over the litres of the fills
/// after the first up to and including the closing one (the same rule as
/// the efficiency calculator). Km outside any closed stretch use
/// [averageKmL]. Null for a trip with no km, or when some km have no km/L
/// at all. [chrono] is the vehicle's fill-ups, oldest first.
TripFuel? tripFuel(Trip trip, List<FuelLog> chrono,
    {required int endOdometer, required double? averageKmL}) {
  final start = trip.startOdometer;
  final end = endOdometer;
  if (end <= start) return null;

  final segments = <(int, int, double)>[];
  var open = -1;
  for (var i = 0; i < chrono.length; i++) {
    if (!chrono[i].fullTank) continue;
    if (open >= 0) {
      final dist = chrono[i].odometer - chrono[open].odometer;
      var litres = 0.0;
      for (var j = open + 1; j <= i; j++) {
        litres += chrono[j].liters;
      }
      if (dist > 0 && litres > 0) {
        segments.add((chrono[open].odometer, chrono[i].odometer, dist / litres));
      }
    }
    open = i;
  }
  segments.sort((a, b) => a.$1.compareTo(b.$1));

  final pieces = <TripPiece>[];
  var cursor = start;
  bool fillGap(int to) {
    if (to <= cursor) return true;
    final avg = averageKmL;
    if (avg == null || avg <= 0) return false;
    pieces.add(TripPiece(cursor, to, avg, false));
    cursor = to;
    return true;
  }

  for (final (from, to, kmL) in segments) {
    if (to <= cursor) continue;
    if (from >= end) break;
    if (!fillGap(math.min(from, end))) return null;
    final pieceEnd = math.min(to, end);
    if (pieceEnd > cursor) {
      pieces.add(TripPiece(cursor, pieceEnd, kmL, true));
      cursor = pieceEnd;
    }
    if (cursor >= end) break;
  }
  if (!fillGap(end)) return null;

  final litres = pieces.fold<double>(0, (s, p) => s + p.litres);
  final allClosed = pieces.every((p) => p.closed);
  bool fullAt(int km) => chrono.any((l) => l.fullTank && l.odometer == km);
  final quality = !allClosed
      ? FuelQuality.estimate
      : fullAt(start) && fullAt(end)
          ? FuelQuality.exact
          : FuelQuality.measured;

  // Price: the trip's own fill-ups, litre-weighted; else the last priced
  // fill-up at or before the start.
  double? price;
  var spend = 0.0, priced = 0.0;
  for (final l in chrono.where((l) => l.tripId == trip.id)) {
    final p = l.pricePerLitre ?? computePricePerLitre(l.totalCost, l.liters);
    if (p == null) continue;
    spend += p * l.liters;
    priced += l.liters;
  }
  if (priced > 0) {
    price = spend / priced;
  } else {
    final started = DateTime.tryParse(trip.startAt);
    for (final l in chrono.reversed) {
      final at = DateTime.tryParse(l.timestamp);
      if (started != null && at != null && at.isAfter(started)) continue;
      price = l.pricePerLitre ?? computePricePerLitre(l.totalCost, l.liters);
      if (price != null) break;
    }
  }

  return TripFuel(
    litres: litres,
    quality: quality,
    pieces: pieces,
    pricePerLitre: price,
    cost: price == null ? null : litres * price,
  );
}
