import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../services/history_pdf.dart';
import '../utils/service_csv.dart';
import '../utils/trip_csv.dart';
import '../utils/vehicle_manager.dart';

import 'settings/data_section.dart';
import 'settings/drive_section.dart';
import 'settings/settings_widgets.dart';

/// CSV import and export, backup files and Google Drive backup, opened from
/// Settings.
class ImportExportScreen extends StatelessWidget {
  /// A restore finished; true when it replaced everything.
  final Future<void> Function(bool replaced) onRestored;

  const ImportExportScreen({super.key, required this.onRestored});

  /// Into the active vehicle, as the fuel CSV import does.
  Future<void> _importServices(BuildContext context) async {
    try {
      final vehicle = await loadActiveVehicle();
      final n = await importServicesCsv(vehicleId: vehicle.id);
      if (n == null || !context.mounted) return;
      showSettingsSnack(context,
          'Imported $n ${n == 1 ? 'service' : 'services'} into ${vehicle.name}.');
    } catch (e) {
      if (context.mounted) showSettingsSnack(context, 'Import failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import and export')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          DataSection(onRestored: onRestored),
          const SizedBox(height: 32),
          sectionHeader('Service CSV'),
          const SizedBox(height: 12),
          settingsGroup([
            SettingsRow(
              icon: Icons.description_outlined,
              label: 'Service CSV template',
              onTap: exportServiceTemplate,
            ),
            SettingsRow(
              icon: Icons.upload_file_outlined,
              label: 'Import services from CSV',
              onTap: () => _importServices(context),
            ),
          ]),
          const SizedBox(height: 32),
          sectionHeader('Trips and history'),
          const SizedBox(height: 12),
          settingsGroup([
            SettingsRow(
              icon: Icons.route_outlined,
              label: 'Trips (CSV)',
              onTap: () async {
                try {
                  final n = await exportTripsCsv();
                  if (n == 0 && context.mounted) {
                    showSettingsSnack(context, 'No trips yet.');
                  }
                } catch (e) {
                  if (context.mounted) {
                    showSettingsSnack(context, 'Export failed: $e');
                  }
                }
              },
            ),
            SettingsRow(
              icon: Icons.picture_as_pdf_outlined,
              label: 'Vehicle history (PDF)',
              onTap: () async {
                final v = await loadActiveVehicle();
                if (!context.mounted) return;
                showSettingsSnack(context, 'Making the PDF for ${v.name}…');
                try {
                  await shareVehicleHistory(v);
                } catch (e) {
                  if (context.mounted) {
                    showSettingsSnack(context, "Couldn't make the PDF: $e");
                  }
                }
              },
            ),
          ]),
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
