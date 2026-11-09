import 'dart:math';

/// The kinds of part tracked, with their labels.
const kPartKinds = {'tyre': 'Tyre', 'battery': 'Battery', 'other': 'Other'};

/// A part that wears out: a tyre, the battery. Its life is in km, months or
/// both; whichever runs out first counts.
class Part {
  final String id;
  final String vehicleId;

  /// A key of [kPartKinds].
  final String kind;

  /// "Front tyre", "Rear tyre", "Battery".
  final String label;
  final String brand;

  /// yyyy-MM-dd the part was fitted.
  final String fittedAt;
  final int fittedOdometer;
  final int? lifeKm;
  final int? lifeMonths;

  /// yyyy-MM-dd, or null.
  final String? warrantyUntil;
  final String notes;

  const Part({
    required this.id,
    required this.vehicleId,
    required this.kind,
    required this.label,
    this.brand = '',
    required this.fittedAt,
    required this.fittedOdometer,
    this.lifeKm,
    this.lifeMonths,
    this.warrantyUntil,
    this.notes = '',
  });

  /// How much of its life is used, 0 to 1 and beyond: the larger of km
  /// used over [lifeKm] and months used over [lifeMonths]. Null with
  /// neither life set.
  double? wear(int odometer, DateTime now) {
    final fitted = DateTime.tryParse(fittedAt);
    double? byKm, byMonths;
    if (lifeKm != null && lifeKm! > 0) {
      byKm = (odometer - fittedOdometer).clamp(0, 1 << 30) / lifeKm!;
    }
    if (lifeMonths != null && lifeMonths! > 0 && fitted != null) {
      byMonths = now.difference(fitted).inDays / 30.44 / lifeMonths!;
    }
    if (byKm == null) return byMonths;
    if (byMonths == null) return byKm;
    return max(byKm, byMonths);
  }

  /// The date the life in months runs out, or null.
  DateTime? get dueDate {
    final fitted = DateTime.tryParse(fittedAt);
    if (fitted == null || lifeMonths == null || lifeMonths! <= 0) return null;
    return DateTime(fitted.year, fitted.month + lifeMonths!, fitted.day);
  }

  static String generateId() =>
      'k${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1000)}';

  Map<String, dynamic> toMap() => {
        'id': id,
        'vehicleId': vehicleId,
        'kind': kind,
        'label': label,
        'brand': brand,
        'fittedAt': fittedAt,
        'fittedOdometer': fittedOdometer,
        'lifeKm': lifeKm,
        'lifeMonths': lifeMonths,
        'warrantyUntil': warrantyUntil,
        'notes': notes,
      };

  factory Part.fromMap(Map<String, dynamic> m) => Part(
        id: m['id'] as String,
        vehicleId: m['vehicleId'] as String,
        kind: kPartKinds.containsKey(m['kind']) ? m['kind'] as String : 'other',
        label: m['label'] as String? ?? '',
        brand: m['brand'] as String? ?? '',
        fittedAt: m['fittedAt'] as String,
        fittedOdometer: (m['fittedOdometer'] as num).toInt(),
        lifeKm: (m['lifeKm'] as num?)?.toInt(),
        lifeMonths: (m['lifeMonths'] as num?)?.toInt(),
        warrantyUntil: m['warrantyUntil'] as String?,
        notes: m['notes'] as String? ?? '',
      );
}
