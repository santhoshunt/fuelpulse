import 'dart:math';

/// A petrol pump you fill up at: a named station of one brand ("MG Road",
/// Bharat Petroleum). [name] may be empty for a pump known only by brand,
/// as the schema 4 migration creates them.
class Pump {
  final String id;
  final String name;
  final String brand;

  /// Pre-selected in the refill form.
  final bool isFavourite;
  final int sortOrder;
  final String createdAt;

  const Pump({
    required this.id,
    required this.name,
    required this.brand,
    this.isFavourite = false,
    this.sortOrder = 0,
    required this.createdAt,
  });

  static String generateId() =>
      'p${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1000)}';

  /// Brand first, then the station: "Bharat Petroleum · MG Road".
  String get label => name.isEmpty ? brand : '$brand · $name';

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'brand': brand,
        'isFavourite': isFavourite ? 1 : 0,
        'sortOrder': sortOrder,
        'createdAt': createdAt,
      };

  factory Pump.fromMap(Map<String, dynamic> m) => Pump(
        id: m['id'] as String,
        name: m['name'] as String? ?? '',
        brand: m['brand'] as String? ?? '',
        isFavourite: ((m['isFavourite'] as num?) ?? 0) == 1,
        sortOrder: (m['sortOrder'] as num?)?.toInt() ?? 0,
        createdAt: m['createdAt'] as String? ?? '',
      );

  Pump copyWith(
          {String? name, String? brand, bool? isFavourite, int? sortOrder}) =>
      Pump(
        id: id,
        name: name ?? this.name,
        brand: brand ?? this.brand,
        isFavourite: isFavourite ?? this.isFavourite,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt,
      );
}
