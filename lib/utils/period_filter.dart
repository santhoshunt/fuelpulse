import '../models/fuel_log.dart';

/// First day of the window covering the current month and the
/// [months] − 1 before it: 6 in November starts on 1 June.
DateTime periodStart(int months, {DateTime? now}) {
  final n = now ?? DateTime.now();
  return DateTime(n.year, n.month - months + 1);
}

enum PeriodKind { last12, overall, custom }

/// The period every Analytics card shows: the last 12 months, everything,
/// or a custom range from [from] to [to] (whole days).
class AnalyticsPeriod {
  final PeriodKind kind;
  final DateTime? from, to;

  const AnalyticsPeriod(this.kind, {this.from, this.to});
}

/// The period's first and last instant. Last 12 months starts on the first
/// of the month 11 months back; Overall on the first log's month.
({DateTime from, DateTime to}) periodRange(AnalyticsPeriod p, List<FuelLog> chrono,
    {DateTime? now}) {
  final n = now ?? DateTime.now();
  switch (p.kind) {
    case PeriodKind.last12:
      return (from: periodStart(12, now: n), to: n);
    case PeriodKind.overall:
      final first = chrono.isEmpty ? null : DateTime.tryParse(chrono.first.timestamp);
      return (
        from: first == null ? periodStart(12, now: n) : DateTime(first.year, first.month),
        to: n,
      );
    case PeriodKind.custom:
      final f = p.from ?? n, t = p.to ?? n;
      return (
        from: DateTime(f.year, f.month, f.day),
        to: DateTime(t.year, t.month, t.day, 23, 59, 59),
      );
  }
}

/// The first day of each month from [from]'s month to [to]'s, in order.
List<DateTime> monthsBetween(DateTime from, DateTime to) => [
      for (var m = DateTime(from.year, from.month);
          !m.isAfter(DateTime(to.year, to.month));
          m = DateTime(m.year, m.month + 1))
        m,
    ];

/// The logs needed for every full-tank segment that closes between [from]
/// and [to]: from the last full tank before [from] (which opens the first
/// such segment) up to [to]. [chrono] is oldest first.
List<FuelLog> logsInRange(List<FuelLog> chrono, DateTime from, DateTime to) {
  var start = 0;
  for (var i = 0; i < chrono.length; i++) {
    final at = DateTime.tryParse(chrono[i].timestamp);
    if (at == null || !at.isBefore(from)) break;
    if (chrono[i].fullTank) start = i;
  }
  return [
    for (final l in chrono.sublist(start))
      if (!(DateTime.tryParse(l.timestamp)?.isAfter(to) ?? false)) l,
  ];
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
