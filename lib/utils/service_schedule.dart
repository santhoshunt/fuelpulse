import 'dart:math' as math;

import '../models/service_record.dart';

/// The next service due: the record that scheduled it and how far off it is.
class NextService {
  final ServiceRecord record;

  /// Null when the schedule has no km, or the odometer is unknown.
  final int? kmLeft;

  /// Null when the schedule has no date.
  final int? daysLeft;

  const NextService(this.record, {this.kmLeft, this.daysLeft});

  bool get overdue => (kmLeft ?? 1) <= 0 || (daysLeft ?? 1) < 0;

  /// How much of the interval has gone, 0 to 1: by km when both are known,
  /// else by date.
  double progress({DateTime? now}) {
    final r = record;
    final due = r.nextDueKm;
    if (due != null && kmLeft != null && due > r.odometer) {
      return (1 - kmLeft! / (due - r.odometer)).clamp(0.0, 1.0);
    }
    final start = DateTime.tryParse(r.timestamp);
    final end = r.nextDueDate == null ? null : DateTime.tryParse(r.nextDueDate!);
    if (start != null && end != null && end.isAfter(start)) {
      final n = now ?? DateTime.now();
      return (n.difference(start).inHours / end.difference(start).inHours)
          .clamp(0.0, 1.0);
    }
    return 0;
  }
}

/// Rough km a day, only to compare a km-based schedule with a date-based
/// one when choosing which comes first.
const _kmPerDay = 30;

/// The schedule due soonest among [records] (any order). A record's
/// schedule stays open until a later record shares one of its service
/// types: an oil change does not cancel a general service that is due.
NextService? nextServiceFor(List<ServiceRecord> records, int? currentOdometer,
    {DateTime? now}) {
  final today = now ?? DateTime.now();
  final byDate = [...records]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  NextService? best;
  double bestScore = double.infinity;
  for (var i = 0; i < byDate.length; i++) {
    final r = byDate[i];
    if (r.nextDueKm == null && r.nextDueDate == null) continue;
    final superseded = byDate
        .skip(i + 1)
        .any((later) => later.typeIds.any(r.typeIds.contains));
    if (superseded) continue;
    final kmLeft = r.nextDueKm != null && currentOdometer != null
        ? r.nextDueKm! - currentOdometer
        : null;
    final dueDate = r.nextDueDate == null ? null : DateTime.tryParse(r.nextDueDate!);
    final daysLeft = dueDate == null
        ? null
        : DateTime(dueDate.year, dueDate.month, dueDate.day)
            .difference(DateTime(today.year, today.month, today.day))
            .inDays;
    if (kmLeft == null && daysLeft == null) continue;
    final score = math.min(kmLeft?.toDouble() ?? double.infinity,
        daysLeft == null ? double.infinity : daysLeft * _kmPerDay.toDouble());
    if (score < bestScore) {
      bestScore = score;
      best = NextService(r, kmLeft: kmLeft, daysLeft: daysLeft);
    }
  }
  return best;
}
