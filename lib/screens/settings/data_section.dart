import 'package:flutter/material.dart';
import '../../db/database_helper.dart';
import '../../utils/vehicle_manager.dart';
import '../../services/backup_file.dart';
import '../../services/backup_payload.dart';
import '../../utils/constants.dart';
import '../../utils/csv_helper.dart';
import 'restore_mode_dialog.dart';
import 'settings_widgets.dart';

/// CSV and backup-file export/import.
class DataSection extends StatelessWidget {
  /// Called after any restore, with whether it was a replace (which also
  /// rewrote settings and lists) or a merge (which can add vehicles).
  final Future<void> Function(bool replaced) onRestored;

  const DataSection({super.key, required this.onRestored});

  static final _db = DatabaseHelper();

  /// CSV carries no vehicle, so export and import work on the active one.
  Future<void> _exportData(BuildContext context) async {
    final vehicle = await loadActiveVehicle();
    final logs = await _db.getAllLogs(vehicle.id);
    if (logs.isEmpty) {
      if (context.mounted) {
        showSettingsSnack(context, '${vehicle.name} has no fill-ups to export.');
      }
      return;
    }
    try {
      await exportCsv(logs, vehicleName: vehicle.name);
    } catch (e) {
      if (context.mounted) showSettingsSnack(context, 'Export failed: $e');
    }
  }

  Future<void> _importData(BuildContext context) async {
    try {
      final vehicle = await loadActiveVehicle();
      final logs = await importCsv(vehicleId: vehicle.id);
      if (logs == null) return; // cancelled
      if (logs.isEmpty) {
        if (context.mounted) {
          showSettingsSnack(context, 'No valid entries found in CSV.');
        }
        return;
      }
      await _db.insertLogs(logs);
      if (context.mounted) {
        showSettingsSnack(
            context, 'Imported ${logs.length} entries into ${vehicle.name}.');
      }
    } on FormatException catch (e) {
      if (context.mounted) {
        showSettingsSnack(context, 'Import error: ${e.message}');
      }
    } catch (e) {
      if (context.mounted) showSettingsSnack(context, 'Import failed: $e');
    }
  }

  Future<void> _exportBackup(BuildContext context) async {
    if (await _db.getLogCount() == 0) {
      if (context.mounted) showSettingsSnack(context, 'No data to export.');
      return;
    }
    try {
      await exportBackupFile();
    } catch (e) {
      if (context.mounted) {
        showSettingsSnack(context, 'Backup export failed: $e');
      }
    }
  }

  Future<void> _importBackup(BuildContext context) async {
    try {
      final data = await pickBackupFile();
      if (data == null) return; // cancelled
      final count = await _db.getLogCount();
      if (!context.mounted) return;
      final mode = await showRestoreModeDialog(context,
          title: 'Import Backup File', currentCount: count);
      if (mode == null) return;
      final restored = await restoreBackup(data, replace: mode == 'replace');
      await onRestored(mode == 'replace');
      if (context.mounted) {
        showSettingsSnack(context,
            'Restored $restored ${restored == 1 ? 'entry' : 'entries'}.');
      }
    } on FormatException catch (e) {
      if (context.mounted) showSettingsSnack(context, e.message);
    } catch (e) {
      if (context.mounted) showSettingsSnack(context, 'Import failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionHeader('Data Management'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: actionCard(
                icon: Icons.upload_file,
                label: 'Export CSV',
                onTap: () => _exportData(context),
                accent: accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: actionCard(
                icon: Icons.download,
                label: 'Import CSV',
                onTap: () => _importData(context),
                accent: accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: actionCard(
                icon: Icons.archive_outlined,
                label: 'Export Backup',
                onTap: () => _exportBackup(context),
                accent: accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: actionCard(
                icon: Icons.unarchive_outlined,
                label: 'Import Backup',
                onTap: () => _importBackup(context),
                accent: accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Backup files (.json.gz) carry everything: every vehicle with its '
          'entries and costs, fuel types, pump brands and settings. CSV '
          'carries the current vehicle\'s entries only.',
          style: TextStyle(color: kTextMuted, fontSize: 12),
        ),
      ],
    );
  }
}
