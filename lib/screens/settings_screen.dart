import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import '../models/theme_preference.dart';
import '../services/backup_payload.dart';
import '../services/drive_backup_service.dart';
import '../utils/constants.dart';
import '../utils/csv_helper.dart';
import '../utils/fuel_type_manager.dart' as ftm;
import '../utils/pump_brand_manager.dart' as pbm;
import '../utils/theme_manager.dart' as tm;
import '../widgets/add_fuel_type_dialog.dart';
import '../widgets/brand_badge.dart';
import '../widgets/color_swatch_picker.dart';

class SettingsScreen extends StatefulWidget {
  final ThemePreference currentTheme;
  final ValueChanged<ThemePreference> onThemeChanged;

  const SettingsScreen({
    super.key,
    required this.currentTheme,
    required this.onThemeChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _db = DatabaseHelper();
  final _tankCapController = TextEditingController();
  bool _dangerExpanded = false;
  final _deleteConfirmController = TextEditingController();
  late ThemePreference _theme;
  List<String> _fuelTypes = [kDefaultFuelType];
  List<String> _pumpBrands = List.of(kDefaultPumpBrands);

  @override
  void initState() {
    super.initState();
    _theme = widget.currentTheme;
    _loadCapacity();
    _loadFuelTypes();
    _loadPumpBrands();
  }

  Future<void> _loadFuelTypes() async {
    final types = await ftm.loadFuelTypes();
    if (mounted) setState(() => _fuelTypes = types);
  }

  Future<void> _loadPumpBrands() async {
    final brands = await pbm.loadPumpBrands();
    if (mounted) setState(() => _pumpBrands = brands);
  }

  Future<void> _addFuelType() async {
    final name = await showAddFuelTypeDialog(context);
    if (name == null || name.trim().isEmpty) return;
    final added = await ftm.addFuelType(name);
    if (!added) {
      _showSnack('"${name.trim()}" already exists.');
    }
    await _loadFuelTypes();
  }

  Future<void> _renameFuelType(String from) async {
    final name = await showAddFuelTypeDialog(context,
        title: 'Rename Fuel Type', initial: from);
    if (name == null || name.trim().isEmpty || name.trim() == from) return;
    final updated = await ftm.renameFuelType(from, name);
    if (updated < 0) {
      _showSnack('"${name.trim()}" already exists.');
    } else {
      _showSnack('Renamed. Updated $updated existing '
          '${updated == 1 ? 'entry' : 'entries'}.');
    }
    await _loadFuelTypes();
  }

  Future<void> _deleteFuelType(String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: const Text(
            'Existing entries keep this label on their record; it just '
            "won't be offered for new fill-ups."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: kDanger, foregroundColor: Colors.white),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    await ftm.deleteFuelType(name);
    await _loadFuelTypes();
  }

  Future<void> _addPumpBrand() async {
    final name = await showAddFuelTypeDialog(context,
        title: 'Add Pump Brand', hint: 'e.g. Reliance');
    if (name == null || name.trim().isEmpty) return;
    final added = await pbm.addPumpBrand(name);
    if (!added) {
      _showSnack('"${name.trim()}" already exists.');
    }
    await _loadPumpBrands();
  }

  Future<void> _renamePumpBrand(String from) async {
    final name = await showAddFuelTypeDialog(context,
        title: 'Rename Pump Brand', initial: from, hint: 'e.g. Reliance');
    if (name == null || name.trim().isEmpty || name.trim() == from) return;
    final updated = await pbm.renamePumpBrand(from, name);
    if (updated < 0) {
      _showSnack('"${name.trim()}" already exists.');
    } else {
      _showSnack('Renamed. Updated $updated existing '
          '${updated == 1 ? 'entry' : 'entries'}.');
    }
    await _loadPumpBrands();
  }

  Future<void> _deletePumpBrand(String name) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "$name"?'),
        content: const Text(
            'Existing entries keep this brand on their record; it just '
            "won't be offered for new fill-ups."),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: kDanger, foregroundColor: Colors.white),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    await pbm.deletePumpBrand(name);
    await _loadPumpBrands();
  }

  Future<void> _loadCapacity() async {
    final prefs = await SharedPreferences.getInstance();
    final cap = prefs.getDouble(kTankCapacityKey) ?? 0;
    if (cap > 0) {
      _tankCapController.text = cap.toString();
    }
  }

  Future<void> _saveCapacity() async {
    final val = double.tryParse(_tankCapController.text.trim());
    final prefs = await SharedPreferences.getInstance();
    if (val != null && val > 0) {
      await prefs.setDouble(kTankCapacityKey, val);
      _showSnack('Tank capacity saved: ${val.toStringAsFixed(1)} L');
    } else {
      await prefs.remove(kTankCapacityKey);
      _showSnack('Tank capacity cleared.');
    }
  }

  Future<void> _onThemeChanged(ThemePreference theme) async {
    await tm.saveTheme(theme);
    setState(() => _theme = theme);
    widget.onThemeChanged(theme);
  }

  Future<void> _exportData() async {
    final logs = await _db.getAllLogs();
    if (logs.isEmpty) {
      _showSnack('No data to export.');
      return;
    }
    try {
      await exportCsv(logs);
    } catch (e) {
      _showSnack('Export failed: $e');
    }
  }

  Future<void> _importData() async {
    try {
      final logs = await importCsv();
      if (logs == null) return; // cancelled
      if (logs.isEmpty) {
        _showSnack('No valid entries found in CSV.');
        return;
      }
      await _db.insertLogs(logs);
      _showSnack('Imported ${logs.length} entries.');
    } on FormatException catch (e) {
      _showSnack('Import error: ${e.message}');
    } catch (e) {
      _showSnack('Import failed: $e');
    }
  }

  Future<void> _deleteAllData() async {
    final text = _deleteConfirmController.text.trim();
    if (text != 'DELETE') {
      _showSnack('Type DELETE to confirm.');
      return;
    }
    await _db.deleteAllLogs();
    _deleteConfirmController.clear();
    setState(() => _dangerExpanded = false);
    _showSnack('All data deleted.');
  }

  /// A replace-mode Drive restore rewrote settings prefs (theme, capacity),
  /// fuel types and pump brands — reload every piece of Settings state that
  /// mirrors them.
  Future<void> _onDriveRestoreReplace() async {
    final theme = await tm.loadTheme();
    if (!mounted) return;
    setState(() => _theme = theme);
    widget.onThemeChanged(theme);
    _tankCapController.clear();
    await _loadCapacity();
    await _loadFuelTypes();
    await _loadPumpBrands();
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  void dispose() {
    _tankCapController.dispose();
    _deleteConfirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Tank Capacity ────────────────────────────
            _sectionHeader('Tank Capacity'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _tankCapController,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: 'Capacity (liters)',
                      prefixIcon: Icon(Icons.local_gas_station_outlined),
                      suffixText: 'L',
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _saveCapacity,
                  child: const Text('Save'),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // ── Fuel Types ───────────────────────────────
            _sectionHeader('Fuel Types'),
            const SizedBox(height: 4),
            const Text(
              'Offered in the fill-up form. Renaming updates existing '
              'entries; deleting only removes it from the list.',
              style: TextStyle(color: kTextMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            _editableListCard(
              items: _fuelTypes,
              accent: accent,
              addLabel: 'Add fuel type',
              onAdd: _addFuelType,
              onRename: _renameFuelType,
              onDelete: _deleteFuelType,
            ),
            const SizedBox(height: 32),

            // ── Pump Brands ──────────────────────────────
            _sectionHeader('Pump Brands'),
            const SizedBox(height: 4),
            const Text(
              'Offered in the fill-up form. Renaming updates existing '
              'entries; deleting only removes it from the list.',
              style: TextStyle(color: kTextMuted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            _editableListCard(
              items: _pumpBrands,
              accent: accent,
              addLabel: 'Add pump brand',
              onAdd: _addPumpBrand,
              onRename: _renamePumpBrand,
              onDelete: _deletePumpBrand,
              leadingBuilder: (name) =>
                  BrandBadge(brandName: name, showLabel: false, size: 22),
            ),
            const SizedBox(height: 32),

            // ── Data Management ──────────────────────────
            _sectionHeader('Data Management'),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _actionCard(
                    icon: Icons.upload_file,
                    label: 'Export CSV',
                    onTap: _exportData,
                    accent: accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _actionCard(
                    icon: Icons.download,
                    label: 'Import CSV',
                    onTap: _importData,
                    accent: accent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // ── Google Drive Backup (Android only) ───────
            if (!kIsWeb && Platform.isAndroid) ...[
              _sectionHeader('Google Drive Backup'),
              const SizedBox(height: 12),
              _DriveBackupSection(onRestoredReplace: _onDriveRestoreReplace),
              const SizedBox(height: 32),
            ],

            // ── Theme Color ──────────────────────────────
            _sectionHeader('Theme Color'),
            const SizedBox(height: 12),
            ColorSwatchPicker(
              current: _theme,
              onChanged: _onThemeChanged,
            ),
            const SizedBox(height: 32),

            // ── Danger Zone ──────────────────────────────
            GestureDetector(
              onTap: () =>
                  setState(() => _dangerExpanded = !_dangerExpanded),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: kDanger.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: kDanger.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: kDanger, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Danger Zone',
                        style: TextStyle(
                          color: kDanger,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Icon(
                      _dangerExpanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      color: kDanger,
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Type DELETE to confirm data wipe:',
                      style: TextStyle(color: kTextSecondary, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _deleteConfirmController,
                      decoration: const InputDecoration(
                        hintText: 'Type DELETE',
                        prefixIcon:
                            Icon(Icons.delete_forever, color: kDanger),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 48,
                      child: ElevatedButton(
                        onPressed: _deleteAllData,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kDanger,
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Delete All Data',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    ),
                  ],
                ),
              ),
              crossFadeState: _dangerExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 300),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        color: kTextPrimary,
        fontSize: 18,
        fontWeight: FontWeight.bold,
      ),
    );
  }

  /// Rounded card listing editable names, each with rename/delete buttons,
  /// plus a pinned add row. Used by the Fuel Types and Pump Brands sections.
  /// Delete is disabled on the last remaining item.
  Widget _editableListCard({
    required List<String> items,
    required Color accent,
    required String addLabel,
    required VoidCallback onAdd,
    required void Function(String) onRename,
    required void Function(String) onDelete,
    Widget Function(String)? leadingBuilder,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
            Padding(
              padding: const EdgeInsets.only(left: 16),
              child: Row(
                children: [
                  if (leadingBuilder != null) ...[
                    leadingBuilder(items[i]),
                    const SizedBox(width: 10),
                  ],
                  Expanded(
                    child: Text(
                      items[i],
                      style:
                          const TextStyle(color: kTextPrimary, fontSize: 14),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.edit_outlined,
                        size: 18, color: accent.withValues(alpha: 0.7)),
                    onPressed: () => onRename(items[i]),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        size: 18,
                        color: items.length > 1
                            ? kDanger.withValues(alpha: 0.7)
                            : kTextMuted.withValues(alpha: 0.4)),
                    onPressed:
                        items.length > 1 ? () => onDelete(items[i]) : null,
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ),
          ],
          Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
          TextButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add, size: 18),
            label: Text(addLabel),
          ),
        ],
      ),
    );
  }

  Widget _actionCard({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color accent,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: [
            Icon(icon, color: accent, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(color: kTextSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Google Drive backup section ─────────────────────────────────────────

class _DriveBackupSection extends StatefulWidget {
  /// Called after a replace-mode restore rewrote settings and fuel types.
  final Future<void> Function() onRestoredReplace;

  const _DriveBackupSection({required this.onRestoredReplace});

  @override
  State<_DriveBackupSection> createState() => _DriveBackupSectionState();
}

class _DriveBackupSectionState extends State<_DriveBackupSection> {
  final _svc = DriveBackupService();
  final _db = DatabaseHelper();

  bool _loading = true;
  GoogleSignInAccount? _account;
  String _freq = 'daily';
  DateTime? _lastBackup;
  String? _lastError;
  bool _uploading = false;
  bool _restoring = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    GoogleSignInAccount? account;
    try {
      account = await _svc.currentUser;
    } catch (_) {
      // Platform channel unavailable (tests, unsupported OS) — treat as
      // signed out rather than crashing Settings.
      account = null;
    }
    final freq = await _svc.getFrequency();
    final last = await _svc.lastBackupAt();
    final error = await _svc.lastError();
    if (!mounted) return;
    setState(() {
      _account = account;
      _freq = freq;
      _lastBackup = last;
      _lastError = error;
      _loading = false;
    });
  }

  Future<void> _connect() async {
    GoogleSignInAccount? account;
    try {
      account = await _svc.signIn();
    } catch (_) {
      account = null;
    }
    if (account == null && mounted) {
      // The classic symptom of a missing/mismatched OAuth Android client is
      // a null result with no error — name the likely cause.
      _showSnack(
        'Google sign-in was cancelled or failed. If this keeps happening, '
        'the OAuth Android client (package name + SHA-1) may be missing.',
      );
    }
    // Full reload — last-backup/error state is account-scoped.
    await _load();
  }

  Future<void> _disconnect() async {
    await _svc.signOut();
    await _load();
  }

  Future<void> _backupNow() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    try {
      // Snapshot before uploadNow's first network await.
      final payload = await buildBackupPayload();
      final name = await _svc.uploadNow(payload);
      if (mounted) _showSnack('Saved to Drive: $name');
    } catch (e) {
      if (mounted) _showSnack('Backup failed: $e');
    } finally {
      if (mounted) {
        setState(() => _uploading = false);
        await _load();
      }
    }
  }

  Future<void> _restore() async {
    if (_restoring) return;
    final count = await _db.getLogCount();
    if (!mounted) return;
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from Drive'),
        content: Text(
          'Merge adds backup entries not already on this device (matched '
          'by id). Replace deletes your current $count '
          '${count == 1 ? 'entry' : 'entries'}, then restores the backup — '
          'including settings, fuel types and pump brands.',
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, 'merge'),
              child: const Text('Merge')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, 'replace'),
              child: const Text('Replace')),
        ],
      ),
    );
    if (mode == null) return;

    setState(() => _restoring = true);
    try {
      final backup = await _svc.downloadLatest();
      final restored =
          await restoreBackup(backup.data, replace: mode == 'replace');
      if (mode == 'replace') {
        await widget.onRestoredReplace();
      }
      if (mounted) {
        _showSnack(
          'Restored $restored ${restored == 1 ? 'entry' : 'entries'} from '
          'backup (${DriveBackupService.formatLastBackup(backup.createdAt)}).',
        );
      }
    } on FormatException catch (e) {
      if (mounted) _showSnack(e.message);
    } catch (e) {
      if (mounted) _showSnack('Restore failed: $e');
    } finally {
      if (mounted) setState(() => _restoring = false);
    }
  }

  Future<void> _setFrequency(String freq) async {
    setState(() => _freq = freq); // optimistic
    await _svc.setFrequency(freq);
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }

    if (_account == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            "Backs up all fill-ups (including costs), fuel types, pump "
            "brands and settings to a "
            "'${DriveBackupService.folderName}' folder in your Google Drive "
            'on the chosen schedule. Off until connected — nothing is '
            'uploaded.',
            style: TextStyle(color: kTextMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          _card(
            icon: Icons.cloud_outlined,
            iconColor: accent,
            label: 'Connect Google Drive',
            onTap: _connect,
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Silent scheduled uploads mean a recorded failure is the one thing
        // this section must never hide.
        if (_lastError != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.3)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.cloud_off_outlined,
                    color: Color(0xFFF59E0B), size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'The last Drive backup failed: $_lastError',
                    style: const TextStyle(
                        color: Color(0xFFF59E0B), fontSize: 12),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        // Account + last backup + disconnect
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Row(
            children: [
              Icon(Icons.account_circle_outlined, color: accent, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _account!.email,
                      style: const TextStyle(
                          color: kTextPrimary, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Last backup: '
                      '${DriveBackupService.formatLastBackup(_lastBackup)}',
                      style: const TextStyle(
                          color: kTextMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              TextButton(
                onPressed: _disconnect,
                child: const Text('Disconnect',
                    style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Frequency
        Row(
          children: [
            const Text('Frequency',
                style: TextStyle(color: kTextSecondary, fontSize: 13)),
            const Spacer(),
            for (final f in ['daily', 'weekly', 'monthly']) ...[
              Padding(
                padding: const EdgeInsets.only(left: 6),
                child: ChoiceChip(
                  label: Text(DriveBackupService.freqLabel(f),
                      style: const TextStyle(fontSize: 12)),
                  selected: _freq == f,
                  onSelected: (_) => _setFrequency(f),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),

        // Back up now / Restore
        Row(
          children: [
            Expanded(
              child: _card(
                icon: _uploading ? null : Icons.cloud_upload_outlined,
                iconColor: accent,
                label: _uploading ? 'Backing up…' : 'Back up now',
                onTap: _backupNow,
                busy: _uploading,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _card(
                icon: _restoring ? null : Icons.cloud_download_outlined,
                iconColor: accent,
                label: _restoring ? 'Restoring…' : 'Restore',
                onTap: _restore,
                busy: _restoring,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _card({
    required IconData? icon,
    required Color iconColor,
    required String label,
    required VoidCallback onTap,
    bool busy = false,
  }) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: [
            if (busy)
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(icon, color: iconColor, size: 28),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(color: kTextSecondary, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }
}
