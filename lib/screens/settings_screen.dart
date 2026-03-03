import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import '../models/theme_preference.dart';
import '../utils/constants.dart';
import '../utils/csv_helper.dart';
import '../utils/theme_manager.dart' as tm;
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

  @override
  void initState() {
    super.initState();
    _theme = widget.currentTheme;
    _loadCapacity();
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
            // ── Theme Color ──────────────────────────────
            _sectionHeader('Theme Color'),
            const SizedBox(height: 12),
            ColorSwatchPicker(
              current: _theme,
              onChanged: _onThemeChanged,
            ),
            const SizedBox(height: 32),

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
