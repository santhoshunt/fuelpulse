import 'dart:math';

/// A bill, receipt or document photo, or a PDF, kept with a service, a
/// fill-up or a paper. The file sits in the pictures folder, so backups
/// carry it with the other pictures.
class Attachment {
  final String id;

  /// 'service', 'fuel' or 'paper'.
  final String ownerType;
  final String ownerId;

  /// File name in the pictures folder.
  final String file;

  /// 'image' or 'pdf'.
  final String kind;
  final String createdAt;

  const Attachment({
    required this.id,
    required this.ownerType,
    required this.ownerId,
    required this.file,
    required this.kind,
    required this.createdAt,
  });

  bool get isPdf => kind == 'pdf';

  static String generateId() =>
      'a${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(1000)}';

  Map<String, dynamic> toMap() => {
        'id': id,
        'ownerType': ownerType,
        'ownerId': ownerId,
        'file': file,
        'kind': kind,
        'createdAt': createdAt,
      };

  factory Attachment.fromMap(Map<String, dynamic> m) => Attachment(
        id: m['id'] as String,
        ownerType: m['ownerType'] as String,
        ownerId: m['ownerId'] as String,
        file: m['file'] as String,
        kind: m['kind'] as String? ?? 'image',
        createdAt: m['createdAt'] as String? ?? '',
      );

  Attachment copyWith({String? ownerId}) => Attachment(
        id: id,
        ownerType: ownerType,
        ownerId: ownerId ?? this.ownerId,
        file: file,
        kind: kind,
        createdAt: createdAt,
      );
}
