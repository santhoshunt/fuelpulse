import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'settings/data_section.dart';
import 'settings/drive_section.dart';
import 'settings/settings_widgets.dart';

/// CSV import and export, backup files and Google Drive backup, opened from
/// Settings.
class ImportExportScreen extends StatelessWidget {
  /// A restore finished; true when it replaced everything.
  final Future<void> Function(bool replaced) onRestored;

  const ImportExportScreen({super.key, required this.onRestored});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import and export')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          DataSection(onRestored: onRestored),
          // google_sign_in 6.x only has an Android implementation here.
          if (!kIsWeb && Platform.isAndroid) ...[
            const SizedBox(height: 32),
            sectionHeader('Google Drive Backup'),
            const SizedBox(height: 12),
            DriveBackupSection(onRestored: onRestored),
          ],
        ],
      ),
    );
  }
}
