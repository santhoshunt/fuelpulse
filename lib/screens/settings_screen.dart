import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../models/theme_preference.dart';
import '../utils/theme_manager.dart' as tm;
import 'settings/about_section.dart';
import 'settings/danger_section.dart';
import 'settings/data_section.dart';
import 'settings/drive_section.dart';
import 'settings/lists_section.dart';
import 'settings/settings_widgets.dart';
import 'settings/theme_section.dart';
import 'settings/vehicles_section.dart';

export 'settings/restore_mode_dialog.dart' show showRestoreModeDialog;

/// Settings is a column of independent sections, one file each under
/// settings/.
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
  late ThemePreference _theme;

  /// Bumped after any restore or data wipe. Sections that mirror stored
  /// data are keyed on it, so they rebuild and read storage again.
  int _reloadToken = 0;

  @override
  void initState() {
    super.initState();
    _theme = widget.currentTheme;
  }

  Future<void> _onThemeChanged(ThemePreference theme) async {
    await tm.saveTheme(theme);
    setState(() => _theme = theme);
    widget.onThemeChanged(theme);
  }

  /// A restore (Drive or backup file) or a data wipe changed what Settings
  /// shows. A merge can add vehicles; a replace also rewrites the theme,
  /// fuel types and pump brands. Reload every section that mirrors them.
  Future<void> _onDataChanged({bool themeChanged = false}) async {
    final theme = themeChanged ? await tm.loadTheme() : _theme;
    if (!mounted) return;
    setState(() {
      _theme = theme;
      _reloadToken++;
    });
    if (themeChanged) widget.onThemeChanged(theme);
  }

  Future<void> _onRestored(bool replaced) =>
      _onDataChanged(themeChanged: replaced);

  @override
  Widget build(BuildContext context) {
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
            VehiclesSection(key: ValueKey('vehicles$_reloadToken')),
            const SizedBox(height: 32),
            ListsSection(key: ValueKey('lists$_reloadToken')),
            const SizedBox(height: 32),
            DataSection(onRestored: _onRestored),
            const SizedBox(height: 32),

            // ── Google Drive Backup (Android only) ───────
            if (!kIsWeb && Platform.isAndroid) ...[
              sectionHeader('Google Drive Backup'),
              const SizedBox(height: 12),
              DriveBackupSection(onRestored: _onRestored),
              const SizedBox(height: 32),
            ],

            ThemeSection(current: _theme, onChanged: _onThemeChanged),
            const SizedBox(height: 32),
            AboutSection(),
            const SizedBox(height: 32),
            DangerSection(onDeleted: _onDataChanged),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
