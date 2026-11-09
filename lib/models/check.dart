import 'dart:math';

/// Something you check yourself on a schedule, with no workshop visit:
/// tyre pressure every 14 days, chain lube every 500 km. Done resets it.
class Check {
  final String id;
  final String vehicleId;
  final String name;
  final int? everyDays;
  final int? everyKm;

  /// When it was last done (ISO), and the odometer then.
  final String lastDoneAt;
  final int lastDoneKm;

  const Check({
    required this.id,
    required this.vehicleId,
    required this.name,
    this.everyDays,
    this.everyKm,
    required this.lastDoneAt,
    this.lastDoneKm = 0,
  });

  DateTime? get dueDate {
    final last = DateTime.tryParse(lastDoneAt);
    if (last == null || everyDays == null || everyDays! <= 0) return null;
    return DateTime(last.year, last.month, last.day + everyDays!);
  }

  int? get dueKm =>
      everyKm == null || everyKm! <= 0 ? null : lastDoneKm + everyKm!;

  /// Days until the due date (negative when past), or null.
  int? daysLeft(DateTime now) {
    final due = dueDate;
    if (due == null) return null;
    return due.difference(DateTime(now.year, now.month, now.day)).inDays;
  }

  /// Km until the due odometer (negative when past), or null.
  int? kmLeft(int? odometer) {
    final due = dueKm;
    return due == null || odometer == null ? null : due - odometer;
  }

  bool isDue(DateTime now, int? odometer) =>
      (daysLeft(now) ?? 1) <= 0 || (kmLeft(odometer) ?? 1) <= 0;

  static String generateId() =>
      'q${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1000)}';

  Map<String, dynamic> toMap() => {
        'id': id,
        'vehicleId': vehicleId,
        'name': name,
        'everyDays': everyDays,
        'everyKm': everyKm,
        'lastDoneAt': lastDoneAt,
        'lastDoneKm': lastDoneKm,
      };

  factory Check.fromMap(Map<String, dynamic> m) => Check(
        id: m['id'] as String,
        vehicleId: m['vehicleId'] as String,
        name: m['name'] as String? ?? '',
        everyDays: (m['everyDays'] as num?)?.toInt(),
        everyKm: (m['everyKm'] as num?)?.toInt(),
        lastDoneAt: m['lastDoneAt'] as String? ?? '',
        lastDoneKm: (m['lastDoneKm'] as num?)?.toInt() ?? 0,
      );

  Check copyWith({
    String? name,
    int? everyDays,
    bool clearEveryDays = false,
    int? everyKm,
    bool clearEveryKm = false,
    String? lastDoneAt,
    int? lastDoneKm,
  }) =>
      Check(
        id: id,
        vehicleId: vehicleId,
        name: name ?? this.name,
        everyDays: clearEveryDays ? null : (everyDays ?? this.everyDays),
        everyKm: clearEveryKm ? null : (everyKm ?? this.everyKm),
        lastDoneAt: lastDoneAt ?? this.lastDoneAt,
        lastDoneKm: lastDoneKm ?? this.lastDoneKm,
      );
}
