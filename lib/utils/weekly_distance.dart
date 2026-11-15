/// Monday of [d]'s week, at midnight.
DateTime weekStart(DateTime d) =>
    DateTime(d.year, d.month, d.day - (d.weekday - 1));

/// Odometer [points] in time order, without any below an earlier one: a
/// mistyped or stale reading would read as the vehicle going backwards.
List<(DateTime, int)> cleanOdometer(Iterable<(DateTime, int)> points) {
  final sorted = points.toList()..sort((a, b) => a.$1.compareTo(b.$1));
  final out = <(DateTime, int)>[];
  for (final p in sorted) {
    if (out.isEmpty || p.$2 >= out.last.$2) out.add(p);
  }
  return out;
}

/// Km driven in each week from [from] to [to], weeks starting on Monday,
/// from odometer [points] (fill-ups, readings, trip starts and ends). The
/// km between two points is spread evenly over the time between them, so a
/// week with no reading still gets its share.
List<(DateTime week, double km)> weeklyDistance(
    Iterable<(DateTime, int)> points, DateTime from, DateTime to) {
  final clean = cleanOdometer(points);
  final weeks = [
    for (var w = weekStart(from);
        !w.isAfter(to);
        w = DateTime(w.year, w.month, w.day + 7))
      w,
  ];
  final km = List<double>.filled(weeks.length, 0);
  for (var i = 1; i < clean.length; i++) {
    final (a, kmA) = clean[i - 1];
    final (b, kmB) = clean[i];
    final driven = kmB - kmA;
    if (driven <= 0) continue;
    final span = b.difference(a).inMilliseconds;
    for (var w = 0; w < weeks.length; w++) {
      final start = weeks[w];
      final end = DateTime(start.year, start.month, start.day + 7);
      if (span == 0) {
        // Two points at the same moment: the km lands in that week.
        if (!b.isBefore(start) && b.isBefore(end)) km[w] += driven;
        continue;
      }
      final s = a.isAfter(start) ? a : start;
      final e = b.isBefore(end) ? b : end;
      final overlap = e.difference(s).inMilliseconds;
      if (overlap > 0) km[w] += driven * overlap / span;
    }
  }
  return [for (var i = 0; i < weeks.length; i++) (weeks[i], km[i])];
}
