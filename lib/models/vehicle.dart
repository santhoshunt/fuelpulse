import 'dart:math';

/// Id of the vehicle every pre-v2.0.0 log belongs to. Created by the schema
/// 3 migration and on a fresh install, so it always exists until the user
/// deletes it in favour of another vehicle.
const kDefaultVehicleId = 'default';
const kDefaultVehicleName = 'My vehicle';

enum VehicleType { car, bike, other }

class Vehicle {
  final String id;
  final String name;
  final VehicleType type;

  /// Litres. Null when unknown: the tank level estimate is then hidden.
  final double? tankCapacity;
  final int sortOrder;
  final String createdAt;

  const Vehicle({
    required this.id,
    required this.name,
    this.type = VehicleType.car,
    this.tankCapacity,
    this.sortOrder = 0,
    required this.createdAt,
  });

  static String generateId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(1000);
    return 'v$now-$rand';
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'type': type.name,
        'tankCapacity': tankCapacity,
        'sortOrder': sortOrder,
        'createdAt': createdAt,
      };

  /// Tolerant of backup JSON: an unknown type reads as [VehicleType.other]
  /// and numbers may arrive as either int or double.
  factory Vehicle.fromMap(Map<String, dynamic> map) {
    final typeName = map['type'] as String?;
    final cap = (map['tankCapacity'] as num?)?.toDouble();
    return Vehicle(
      id: map['id'] as String,
      name: map['name'] as String,
      type: VehicleType.values.firstWhere((t) => t.name == typeName,
          orElse: () => VehicleType.other),
      tankCapacity: cap != null && cap > 0 ? cap : null,
      sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 0,
      createdAt: map['createdAt'] as String? ?? '',
    );
  }

  Vehicle copyWith({
    String? name,
    VehicleType? type,
    double? tankCapacity,
    bool clearTankCapacity = false,
    int? sortOrder,
  }) {
    return Vehicle(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      tankCapacity:
          clearTankCapacity ? null : (tankCapacity ?? this.tankCapacity),
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
    );
  }

  @override
  String toString() => 'Vehicle(id: $id, name: $name, cap: $tankCapacity)';
}
