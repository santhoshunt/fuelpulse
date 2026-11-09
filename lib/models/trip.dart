import 'dart:math';

/// One trip: where the odometer stood when it started and ended. An active
/// trip has no end yet. Fill-ups made on it carry its id.
class Trip {
  final String id;
  final String vehicleId;
  final String name;

  /// ISO timestamps, like a fill-up's.
  final String startAt;
  final int startOdometer;
  final String? endAt;
  final int? endOdometer;
  final String notes;

  const Trip({
    required this.id,
    required this.vehicleId,
    required this.name,
    required this.startAt,
    required this.startOdometer,
    this.endAt,
    this.endOdometer,
    this.notes = '',
  });

  bool get isActive => endAt == null;

  static String generateId() =>
      'r${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1000)}';

  Map<String, dynamic> toMap() => {
        'id': id,
        'vehicleId': vehicleId,
        'name': name,
        'startAt': startAt,
        'startOdometer': startOdometer,
        'endAt': endAt,
        'endOdometer': endOdometer,
        'notes': notes,
      };

  factory Trip.fromMap(Map<String, dynamic> m) => Trip(
        id: m['id'] as String,
        vehicleId: m['vehicleId'] as String,
        name: m['name'] as String? ?? '',
        startAt: m['startAt'] as String,
        startOdometer: (m['startOdometer'] as num).toInt(),
        endAt: m['endAt'] as String?,
        endOdometer: (m['endOdometer'] as num?)?.toInt(),
        notes: m['notes'] as String? ?? '',
      );

  Trip copyWith({
    String? name,
    String? startAt,
    int? startOdometer,
    String? endAt,
    int? endOdometer,
    bool clearEnd = false,
    String? notes,
  }) =>
      Trip(
        id: id,
        vehicleId: vehicleId,
        name: name ?? this.name,
        startAt: startAt ?? this.startAt,
        startOdometer: startOdometer ?? this.startOdometer,
        endAt: clearEnd ? null : (endAt ?? this.endAt),
        endOdometer: clearEnd ? null : (endOdometer ?? this.endOdometer),
        notes: notes ?? this.notes,
      );
}
