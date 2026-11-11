import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../db/database_helper.dart';
import '../../utils/vehicle_manager.dart';
import '../../services/backup_file.dart';
import '../../services/backup_payload.dart';
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
          showSettingsSnack(context, 'No fill-ups found in that CSV file.');
        }
        return;
      }
      await _db.insertLogs(logs);
      if (context.mounted) {
        showSettingsSnack(
            context, 'Imported ${logs.length} fill-ups into ${vehicle.name}.');
      }
    } on FormatException catch (e) {
      if (context.mounted) {
        showSettingsSnack(context, 'Import error: ${e.message}');
      }
    } catch (e) {
      if (context.mounted) showSettingsSnack(context, "Couldn't import that file. Check it is a CSV of fill-ups.");
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
        showSettingsSnack(context, "Couldn't export the backup. Try again.");
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
          title: 'Import backup file', currentCount: count);
      if (mode == null) return;
      final restored = await restoreBackup(data, replace: mode == 'replace');
      await onRestored(mode == 'replace');
      if (context.mounted) {
        showSettingsSnack(context,
            'Restored the backup: $restored ${restored == 1 ? 'fill-up' : 'fill-ups'} and everything with them.');
      }
    } on FormatException catch (e) {
      if (context.mounted) showSettingsSnack(context, e.message);
    } catch (e) {
      if (context.mounted) {
        showSettingsSnack(context, "Couldn't restore that file. Check it is a My H'ness backup.");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionHeader('Fill-ups and backup'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: actionCard(
                icon: Icons.upload_file,
                label: 'Export fill-ups (CSV)',
                onTap: () => _exportData(context),
                accent: accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: actionCard(
                icon: Icons.download,
                label: 'Import fill-ups (CSV)',
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
                label: 'Export backup',
                onTap: () => _exportBackup(context),
                accent: accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: actionCard(
                icon: Icons.unarchive_outlined,
                label: 'Import backup',
                onTap: () => _importBackup(context),
                accent: accent,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'A backup file (.json.gz) holds your vehicles, fill-ups, services, '
          'trips, papers, tyres and battery, checks, bills and photos, '
          'pumps, workshops, brands and the app\'s look. Odometer readings '
          'and alert settings stay on this phone. The CSV files hold the '
          'current vehicle\'s fill-ups only.',
          style: TextStyle(color: AppColors.of(context).textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}
