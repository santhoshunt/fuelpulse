import 'dart:math';

class FuelLog {
  final String id;
  final String timestamp;
  final int odometer;
  final double liters;
  final String pumpBrand;
  final bool fullTank;
  final String notes;

  FuelLog({
    required this.id,
    required this.timestamp,
    required this.odometer,
    required this.liters,
    required this.pumpBrand,
    this.fullTank = true,
    this.notes = '',
  });

  /// Generate a unique ID based on current time + random suffix.
  static String generateId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final rand = Random().nextInt(1000);
    return '$now-$rand';
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp,
      'odometer': odometer,
      'liters': liters,
      'pumpBrand': pumpBrand,
      'fullTank': fullTank ? 1 : 0,
      'notes': notes,
    };
  }

  factory FuelLog.fromMap(Map<String, dynamic> map) {
    return FuelLog(
      id: map['id'] as String,
      timestamp: map['timestamp'] as String,
      odometer: map['odometer'] as int,
      liters: (map['liters'] as num).toDouble(),
      pumpBrand: map['pumpBrand'] as String? ?? '',
      fullTank: (map['fullTank'] as int? ?? 1) == 1,
      notes: map['notes'] as String? ?? '',
    );
  }

  FuelLog copyWith({
    String? id,
    String? timestamp,
    int? odometer,
    double? liters,
    String? pumpBrand,
    bool? fullTank,
    String? notes,
  }) {
    return FuelLog(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      odometer: odometer ?? this.odometer,
      liters: liters ?? this.liters,
      pumpBrand: pumpBrand ?? this.pumpBrand,
      fullTank: fullTank ?? this.fullTank,
      notes: notes ?? this.notes,
    );
  }

  @override
  String toString() {
    return 'FuelLog(id: $id, odo: $odometer, liters: $liters, brand: $pumpBrand, full: $fullTank)';
  }
}
