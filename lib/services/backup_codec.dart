import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Shared backup wire format: gzipped UTF-8 JSON. Lives apart from the Drive
/// service so the file export/import feature doesn't pull in google_sign_in.

const backupFilePrefix = 'fuelpulse_backup_';

/// Canonical backup file name: prefix + second-precision ISO timestamp with
/// ':' replaced (illegal on most filesystems), e.g.
/// fuelpulse_backup_2026-09-01T14-30-00.json.gz
String buildBackupFileName(DateTime now) =>
    '$backupFilePrefix${now.toIso8601String().split('.').first.replaceAll(':', '-')}'
    '.json.gz';

/// Gzips the backup map. Top-level so `compute` can ship it to a worker
/// isolate — a large log history gzips ~10x smaller than its JSON.
Uint8List encodeBackupGz(Map<String, dynamic> data) =>
    Uint8List.fromList(gzip.encode(utf8.encode(jsonEncode(data))));

/// Inverse of [encodeBackupGz]. Throws [FormatException] on anything that
/// isn't a gzipped JSON object.
Map<String, dynamic> decodeBackupGz(Uint8List bytes) {
  final List<int> raw;
  try {
    raw = gzip.decode(bytes);
  } catch (_) {
    throw const FormatException('Not a gzip backup file');
  }
  final decoded = jsonDecode(utf8.decode(raw));
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Not a FuelPulse backup file');
  }
  return decoded;
}
