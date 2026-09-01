import 'dart:math';

class FuelLog {
  final String id;
  final String timestamp;
  final int odometer;
  final double liters;
  final String pumpBrand;
  final bool fullTank;
  final String notes;
  final String fuelType;

  /// Total amount paid for this fill-up, in rupees. Null when not recorded.
  final double? totalCost;

  /// Pump rate in rupees per litre. Stored separately from [totalCost]
  /// because both come off the receipt and litres can be edited later —
  /// deriving one from the other would silently rewrite history.
  final double? pricePerLitre;

  FuelLog({
    required this.id,
    required this.timestamp,
    required this.odometer,
    required this.liters,
    required this.pumpBrand,
    this.fullTank = true,
    this.notes = '',
    this.fuelType = 'Normal',
    this.totalCost,
    this.pricePerLitre,
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
      'fuelType': fuelType,
      'totalCost': totalCost,
      'pricePerLitre': pricePerLitre,
    };
  }

  factory FuelLog.fromMap(Map<String, dynamic> map) {
    return FuelLog(
      id: map['id'] as String,
      timestamp: map['timestamp'] as String,
      // `as num` because JSON restore can deliver ints as doubles.
      odometer: (map['odometer'] as num).toInt(),
      liters: (map['liters'] as num).toDouble(),
      pumpBrand: map['pumpBrand'] as String? ?? '',
      fullTank: (map['fullTank'] as int? ?? 1) == 1,
      notes: map['notes'] as String? ?? '',
      fuelType: (map['fuelType'] as String?)?.isNotEmpty == true
          ? map['fuelType'] as String
          : 'Normal',
      totalCost: (map['totalCost'] as num?)?.toDouble(),
      pricePerLitre: (map['pricePerLitre'] as num?)?.toDouble(),
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
    String? fuelType,
    double? totalCost,
    bool clearTotalCost = false,
    double? pricePerLitre,
    bool clearPricePerLitre = false,
  }) {
    return FuelLog(
      id: id ?? this.id,
      timestamp: timestamp ?? this.timestamp,
      odometer: odometer ?? this.odometer,
      liters: liters ?? this.liters,
      pumpBrand: pumpBrand ?? this.pumpBrand,
      fullTank: fullTank ?? this.fullTank,
      notes: notes ?? this.notes,
      fuelType: fuelType ?? this.fuelType,
      totalCost: clearTotalCost ? null : (totalCost ?? this.totalCost),
      pricePerLitre:
          clearPricePerLitre ? null : (pricePerLitre ?? this.pricePerLitre),
    );
  }

  @override
  String toString() {
    return 'FuelLog(id: $id, odo: $odometer, liters: $liters, brand: $pumpBrand, full: $fullTank, type: $fuelType)';
  }
}
