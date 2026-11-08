import 'dart:convert';
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

  /// Make and model, free text ("Royal Enfield Classic 350").
  final String model;

  /// Four ascending km/L limits splitting the five mileage bands; null
  /// means the defaults for [type].
  final List<double>? mileageBands;

  /// Litres. Null when unknown: the tank level estimate is then hidden.
  final double? tankCapacity;
  final int sortOrder;
  final String createdAt;

  const Vehicle({
    required this.id,
    required this.name,
    this.type = VehicleType.car,
    this.model = '',
    this.mileageBands,
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
        'model': model,
        'mileageBands':
            mileageBands == null ? null : jsonEncode(mileageBands),
        'tankCapacity': tankCapacity,
        'sortOrder': sortOrder,
        'createdAt': createdAt,
      };

  /// Tolerant of backup JSON: an unknown type reads as [VehicleType.other]
  /// and numbers may arrive as either int or double.
  factory Vehicle.fromMap(Map<String, dynamic> map) {
    final typeName = map['type'] as String?;
    final cap = (map['tankCapacity'] as num?)?.toDouble();
    // A JSON string in SQLite, a list in backup JSON. Anything but four
    // numbers falls back to the type's defaults.
    List<double>? bands;
    try {
      final raw = map['mileageBands'];
      final list = raw is String ? jsonDecode(raw) : raw;
      if (list is List && list.length == 4) {
        bands = list.map((e) => (e as num).toDouble()).toList();
      }
    } catch (_) {}
    return Vehicle(
      id: map['id'] as String,
      name: map['name'] as String,
      type: VehicleType.values.firstWhere((t) => t.name == typeName,
          orElse: () => VehicleType.other),
      model: map['model'] as String? ?? '',
      mileageBands: bands,
      tankCapacity: cap != null && cap > 0 ? cap : null,
      sortOrder: (map['sortOrder'] as num?)?.toInt() ?? 0,
      createdAt: map['createdAt'] as String? ?? '',
    );
  }

  Vehicle copyWith({
    String? name,
    VehicleType? type,
    String? model,
    List<double>? mileageBands,
    bool clearMileageBands = false,
    double? tankCapacity,
    bool clearTankCapacity = false,
    int? sortOrder,
  }) {
    return Vehicle(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      model: model ?? this.model,
      mileageBands:
          clearMileageBands ? null : (mileageBands ?? this.mileageBands),
      tankCapacity:
          clearTankCapacity ? null : (tankCapacity ?? this.tankCapacity),
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
    );
  }

  @override
  String toString() => 'Vehicle(id: $id, name: $name, cap: $tankCapacity)';
}
