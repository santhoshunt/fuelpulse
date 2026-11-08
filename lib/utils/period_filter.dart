import '../models/fuel_log.dart';

/// First day of the window covering the current month and the
/// [months] − 1 before it: 6 in November starts on 1 June.
DateTime periodStart(int months, {DateTime? now}) {
  final n = now ?? DateTime.now();
  return DateTime(n.year, n.month - months + 1);
}

/// The logs needed to work out every full-tank segment that closes inside
/// the last [months] months: everything from the last full tank before the
/// window (which opens the first such segment) onwards. [chrono] is oldest
/// first.
List<FuelLog> logsInLastMonths(List<FuelLog> chrono, int months,
    {DateTime? now}) {
  final start = periodStart(months, now: now);
  var from = 0;
  for (var i = 0; i < chrono.length; i++) {
    final at = DateTime.tryParse(chrono[i].timestamp);
    if (at == null || !at.isBefore(start)) break;
    if (chrono[i].fullTank) from = i;
  }
  return chrono.sublist(from);
}
