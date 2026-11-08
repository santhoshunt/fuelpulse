import 'dart:math';

/// A garage or service centre a vehicle is serviced at.
class Workshop {
  final String id;
  final String name;
  final String area;
  final String phone;
  final int sortOrder;

  const Workshop({
    required this.id,
    required this.name,
    this.area = '',
    this.phone = '',
    this.sortOrder = 0,
  });

  static String generateId() =>
      'w${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1000)}';

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'area': area,
        'phone': phone,
        'sortOrder': sortOrder,
      };

  factory Workshop.fromMap(Map<String, dynamic> m) => Workshop(
        id: m['id'] as String,
        name: m['name'] as String? ?? '',
        area: m['area'] as String? ?? '',
        phone: m['phone'] as String? ?? '',
        sortOrder: (m['sortOrder'] as num?)?.toInt() ?? 0,
      );

  Workshop copyWith(
          {String? name, String? area, String? phone, int? sortOrder}) =>
      Workshop(
        id: id,
        name: name ?? this.name,
        area: area ?? this.area,
        phone: phone ?? this.phone,
        sortOrder: sortOrder ?? this.sortOrder,
      );
}
