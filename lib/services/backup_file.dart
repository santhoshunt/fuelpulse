import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'backup_codec.dart';
import 'backup_payload.dart';

/// Local backup file export/import — the Drive-independent path. Same
/// payload and gzip wire format as the Drive backup, so a file exported here
/// restores from either path.

/// Snapshot → gzip → temp file → share sheet. Returns the shared file name.
Future<String> exportBackupFile() async {
  // Snapshot before anything slow, mirroring the Drive upload invariant.
  final payload = await buildBackupPayload();
  final bytes =
      await compute(encodeBackupGz, payload, debugLabel: 'encodeBackupGz');
  final name = buildBackupFileName(DateTime.now());
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$name');
  await file.writeAsBytes(bytes);

  await SharePlus.instance.share(ShareParams(
    files: [XFile(file.path, mimeType: 'application/gzip')],
    subject: 'FuelPulse Backup',
  ));
  return name;
}

/// Let the user pick a backup file and decode it. Null when cancelled.
/// Throws [FormatException] for anything that isn't a FuelPulse backup.
///
/// FileType.any on purpose: Android's system picker filters FileType.custom
/// by MIME type, and .json.gz files commonly report application/octet-stream,
/// which would grey out the very file the user is after. Decode validation
/// rejects wrong picks with a clear message instead.
Future<Map<String, dynamic>?> pickBackupFile() async {
  final result = await FilePicker.platform.pickFiles(type: FileType.any);
  final path = result?.files.single.path;
  if (path == null) return null;
  return readBackupFile(File(path));
}

/// Split out from [pickBackupFile] for testability.
Future<Map<String, dynamic>> readBackupFile(File file) async =>
    compute(decodeBackupGz, await file.readAsBytes(),
        debugLabel: 'decodeBackupGz');
