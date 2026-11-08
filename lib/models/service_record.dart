import 'dart:convert';
import 'dart:math';

/// One service visit: when, at what odometer, where, what was done, what it
/// cost, and when the next one is due.
class ServiceRecord {
  final String id;
  final String vehicleId;
  final String timestamp;
  final int odometer;
  final String? workshopId;

  /// [ServiceType] ids. Stored as a JSON list: services are never queried
  /// by type in SQL.
  final List<String> typeIds;
  final double? cost;
  final String notes;
  final int? nextDueKm;

  /// ISO date (yyyy-MM-dd) the next service is due, or null.
  final String? nextDueDate;

  const ServiceRecord({
    required this.id,
    required this.vehicleId,
    required this.timestamp,
    required this.odometer,
    this.workshopId,
    this.typeIds = const [],
    this.cost,
    this.notes = '',
    this.nextDueKm,
    this.nextDueDate,
  });

  static String generateId() =>
      's${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1000)}';

  Map<String, dynamic> toMap() => {
        'id': id,
        'vehicleId': vehicleId,
        'timestamp': timestamp,
        'odometer': odometer,
        'workshopId': workshopId,
        'typeIds': jsonEncode(typeIds),
        'cost': cost,
        'notes': notes,
        'nextDueKm': nextDueKm,
        'nextDueDate': nextDueDate,
      };

  /// [typeIds] may arrive as a JSON string (SQLite) or a list (backup JSON).
  factory ServiceRecord.fromMap(Map<String, dynamic> m) {
    final raw = m['typeIds'];
    List<String> types = const [];
    try {
      final list = raw is String ? jsonDecode(raw) : raw;
      if (list is List) types = list.map((e) => '$e').toList();
    } catch (_) {}
    return ServiceRecord(
      id: m['id'] as String,
      vehicleId: m['vehicleId'] as String,
      timestamp: m['timestamp'] as String,
      odometer: (m['odometer'] as num).toInt(),
      workshopId: m['workshopId'] as String?,
      typeIds: types,
      cost: (m['cost'] as num?)?.toDouble(),
      notes: m['notes'] as String? ?? '',
      nextDueKm: (m['nextDueKm'] as num?)?.toInt(),
      nextDueDate: m['nextDueDate'] as String?,
    );
  }

  ServiceRecord copyWith({
    String? timestamp,
    int? odometer,
    String? workshopId,
    bool clearWorkshop = false,
    List<String>? typeIds,
    double? cost,
    bool clearCost = false,
    String? notes,
    int? nextDueKm,
    bool clearNextDueKm = false,
    String? nextDueDate,
    bool clearNextDueDate = false,
  }) =>
      ServiceRecord(
        id: id,
        vehicleId: vehicleId,
        timestamp: timestamp ?? this.timestamp,
        odometer: odometer ?? this.odometer,
        workshopId: clearWorkshop ? null : (workshopId ?? this.workshopId),
        typeIds: typeIds ?? this.typeIds,
        cost: clearCost ? null : (cost ?? this.cost),
        notes: notes ?? this.notes,
        nextDueKm: clearNextDueKm ? null : (nextDueKm ?? this.nextDueKm),
        nextDueDate:
            clearNextDueDate ? null : (nextDueDate ?? this.nextDueDate),
      );
}
