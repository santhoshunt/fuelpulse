import 'dart:math';

/// A kind of service work (oil change, chain lube) with how often it is
/// usually due. Either interval may be null.
class ServiceType {
  final String id;
  final String name;
  final int? intervalKm;
  final int? intervalMonths;
  final int sortOrder;

  const ServiceType({
    required this.id,
    required this.name,
    this.intervalKm,
    this.intervalMonths,
    this.sortOrder = 0,
  });

  static String generateId() =>
      't${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1000)}';

  /// Seeded on a fresh install and by the schema 4 migration.
  static const defaults = [
    ServiceType(
        id: 'general',
        name: 'General service',
        intervalKm: 3000,
        intervalMonths: 6,
        sortOrder: 0),
    ServiceType(id: 'oil', name: 'Oil change', intervalKm: 3000, sortOrder: 1),
    ServiceType(
        id: 'chain',
        name: 'Chain lube',
        intervalKm: 500,
        intervalMonths: 1,
        sortOrder: 2),
    ServiceType(id: 'brakes', name: 'Brake pads', sortOrder: 3),
    ServiceType(
        id: 'air_filter', name: 'Air filter', intervalKm: 10000, sortOrder: 4),
  ];

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'intervalKm': intervalKm,
        'intervalMonths': intervalMonths,
        'sortOrder': sortOrder,
      };

  factory ServiceType.fromMap(Map<String, dynamic> m) => ServiceType(
        id: m['id'] as String,
        name: m['name'] as String? ?? '',
        intervalKm: (m['intervalKm'] as num?)?.toInt(),
        intervalMonths: (m['intervalMonths'] as num?)?.toInt(),
        sortOrder: (m['sortOrder'] as num?)?.toInt() ?? 0,
      );

  ServiceType copyWith({
    String? name,
    int? intervalKm,
    bool clearIntervalKm = false,
    int? intervalMonths,
    bool clearIntervalMonths = false,
    int? sortOrder,
  }) =>
      ServiceType(
        id: id,
        name: name ?? this.name,
        intervalKm: clearIntervalKm ? null : (intervalKm ?? this.intervalKm),
        intervalMonths: clearIntervalMonths
            ? null
            : (intervalMonths ?? this.intervalMonths),
        sortOrder: sortOrder ?? this.sortOrder,
      );
}
