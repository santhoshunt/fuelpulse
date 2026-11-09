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

  /// Four descending ₹/km limits splitting the five cost bands (lower
  /// cost is better); null means the defaults for [type].
  final List<double>? costBands;

  /// `motorcycle` or `scooter` for a bike, `file:NAME` for the user's own
  /// picture, null for the type's default picture.
  final String? icon;

  /// Litres. Null when unknown: the tank level estimate is then hidden.
  final double? tankCapacity;

  /// Rupees a month for fuel; null when no budget is set.
  final double? monthlyBudget;
  final int sortOrder;
  final String createdAt;

  const Vehicle({
    required this.id,
    required this.name,
    this.type = VehicleType.car,
    this.model = '',
    this.mileageBands,
    this.costBands,
    this.icon,
    this.tankCapacity,
    this.monthlyBudget,
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
        'costBands': costBands == null ? null : jsonEncode(costBands),
        'icon': icon,
        'tankCapacity': tankCapacity,
        'monthlyBudget': monthlyBudget,
        'sortOrder': sortOrder,
        'createdAt': createdAt,
      };

  /// Tolerant of backup JSON: an unknown type reads as [VehicleType.other]
  /// and numbers may arrive as either int or double.
  factory Vehicle.fromMap(Map<String, dynamic> map) {
    final typeName = map['type'] as String?;
    final cap = (map['tankCapacity'] as num?)?.toDouble();
    final budget = (map['monthlyBudget'] as num?)?.toDouble();
    // A JSON string in SQLite, a list in backup JSON. Anything but four
    // numbers falls back to the type's defaults.
    List<double>? four(Object? raw) {
      try {
        final list = raw is String ? jsonDecode(raw) : raw;
        if (list is List && list.length == 4) {
          return list.map((e) => (e as num).toDouble()).toList();
        }
      } catch (_) {}
      return null;
    }
    final bands = four(map['mileageBands']);
    return Vehicle(
      id: map['id'] as String,
      name: map['name'] as String,
      type: VehicleType.values.firstWhere((t) => t.name == typeName,
          orElse: () => VehicleType.other),
      model: map['model'] as String? ?? '',
      mileageBands: bands,
      costBands: four(map['costBands']),
      icon: map['icon'] as String?,
      tankCapacity: cap != null && cap > 0 ? cap : null,
      monthlyBudget: budget != null && budget > 0 ? budget : null,
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
    List<double>? costBands,
    bool clearCostBands = false,
    String? icon,
    bool clearIcon = false,
    double? tankCapacity,
    bool clearTankCapacity = false,
    double? monthlyBudget,
    bool clearMonthlyBudget = false,
    int? sortOrder,
  }) {
    return Vehicle(
      id: id,
      name: name ?? this.name,
      type: type ?? this.type,
      model: model ?? this.model,
      mileageBands:
          clearMileageBands ? null : (mileageBands ?? this.mileageBands),
      costBands: clearCostBands ? null : (costBands ?? this.costBands),
      icon: clearIcon ? null : (icon ?? this.icon),
      tankCapacity:
          clearTankCapacity ? null : (tankCapacity ?? this.tankCapacity),
      monthlyBudget:
          clearMonthlyBudget ? null : (monthlyBudget ?? this.monthlyBudget),
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
    );
  }

  @override
  String toString() => 'Vehicle(id: $id, name: $name, cap: $tankCapacity)';
}
