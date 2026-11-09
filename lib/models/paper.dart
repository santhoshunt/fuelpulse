import 'dart:math';

/// The kinds of paper a vehicle carries, with their labels.
const kPaperKinds = {
  'rc': 'RC',
  'insurance': 'Insurance',
  'puc': 'PUC certificate',
  'licence': 'Driving licence',
  'road_tax': 'Road tax',
  'other': 'Other',
};

/// One document for a vehicle: registration certificate, insurance,
/// Pollution Under Control certificate, licence, road tax or anything else.
/// One with an expiry date gets a reminder before it lapses.
class Paper {
  final String id;
  final String vehicleId;

  /// A key of [kPaperKinds].
  final String kind;

  /// Optional own name; the kind's label is shown when empty.
  final String title;
  final String number;

  /// yyyy-MM-dd, or null.
  final String? issuedOn;
  final String? expiresOn;

  /// Days before [expiresOn] the reminder fires.
  final int remindDays;
  final String notes;

  const Paper({
    required this.id,
    required this.vehicleId,
    required this.kind,
    this.title = '',
    this.number = '',
    this.issuedOn,
    this.expiresOn,
    this.remindDays = 7,
    this.notes = '',
  });

  String get displayName =>
      title.isNotEmpty ? title : (kPaperKinds[kind] ?? 'Paper');

  static String generateId() =>
      'd${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1000)}';

  Map<String, dynamic> toMap() => {
        'id': id,
        'vehicleId': vehicleId,
        'kind': kind,
        'title': title,
        'number': number,
        'issuedOn': issuedOn,
        'expiresOn': expiresOn,
        'remindDays': remindDays,
        'notes': notes,
      };

  factory Paper.fromMap(Map<String, dynamic> m) => Paper(
        id: m['id'] as String,
        vehicleId: m['vehicleId'] as String,
        kind: kPaperKinds.containsKey(m['kind']) ? m['kind'] as String : 'other',
        title: m['title'] as String? ?? '',
        number: m['number'] as String? ?? '',
        issuedOn: m['issuedOn'] as String?,
        expiresOn: m['expiresOn'] as String?,
        remindDays: (m['remindDays'] as num?)?.toInt() ?? 7,
        notes: m['notes'] as String? ?? '',
      );

  Paper copyWith({
    String? kind,
    String? title,
    String? number,
    String? issuedOn,
    bool clearIssuedOn = false,
    String? expiresOn,
    bool clearExpiresOn = false,
    int? remindDays,
    String? notes,
  }) =>
      Paper(
        id: id,
        vehicleId: vehicleId,
        kind: kind ?? this.kind,
        title: title ?? this.title,
        number: number ?? this.number,
        issuedOn: clearIssuedOn ? null : (issuedOn ?? this.issuedOn),
        expiresOn: clearExpiresOn ? null : (expiresOn ?? this.expiresOn),
        remindDays: remindDays ?? this.remindDays,
        notes: notes ?? this.notes,
      );
}
