import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../utils/appearance_prefs.dart';
import '../utils/page_routes.dart';
import 'appearance_screen.dart';
import 'import_export_screen.dart';
import 'settings/about_section.dart';
import 'settings/danger_section.dart';
import 'settings/lists_section.dart';
import 'settings/settings_widgets.dart';
import 'settings/vehicles_section.dart';

export 'settings/restore_mode_dialog.dart' show showRestoreModeDialog;

/// The Settings tab: Vehicles and Lists inline, Data and Appearance as rows
/// that open their own pages, then About and Delete all data. Each section
/// lives in its own file under settings/.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  /// Bumped after any restore or data wipe. Sections that mirror stored
  /// data are keyed on it, so they rebuild and read storage again.
  int _reloadToken = 0;

  /// A restore (Drive or backup file) or a data wipe changed what Settings
  /// shows. A merge can add vehicles; a replace also rewrites the
  /// appearance, fuel types and pump brands. Reload every section that
  /// mirrors them.
  Future<void> _onDataChanged({bool themeChanged = false}) async {
    if (themeChanged) await reloadAppearance();
    if (!mounted) return;
    setState(() => _reloadToken++);
  }

  Future<void> _onRestored(bool replaced) =>
      _onDataChanged(themeChanged: replaced);

  void _open(Widget page) =>
      Navigator.push(context, SmoothPageRoute(page: page));

  static const _modeNames = {
    ThemeMode.light: 'Light',
    ThemeMode.dark: 'Dark',
    ThemeMode.system: 'System',
  };

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final value = TextStyle(color: colors.textSecondary, fontSize: 15);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        // Built in full, not lazily: a short page, and an expanded section
        // at the bottom must exist before it is scrolled to.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Settings',
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.5)),
            const SizedBox(height: 20),
            VehiclesSection(key: ValueKey('vehicles$_reloadToken')),
            const SizedBox(height: 32),
            ListsSection(key: ValueKey('lists$_reloadToken')),
            const SizedBox(height: 32),
            sectionHeader('Data'),
            const SizedBox(height: 12),
            settingsGroup([
              SettingsRow(
                icon: Icons.import_export,
                label: 'Import and export',
                onTap: () =>
                    _open(ImportExportScreen(onRestored: _onRestored)),
              ),
            ]),
            const SizedBox(height: 32),
            sectionHeader('Appearance'),
            const SizedBox(height: 12),
            ValueListenableBuilder<Appearance>(
              valueListenable: appearance,
              builder: (context, a, _) => settingsGroup([
                SettingsRow(
                  icon: Icons.brightness_6_outlined,
                  label: 'Theme',
                  trailing: Text(_modeNames[a.mode]!, style: value),
                  onTap: () => _open(const AppearanceScreen()),
                ),
                SettingsRow(
                  icon: Icons.palette_outlined,
                  label: 'Colour palette',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(colors: [
                            a.palette.primary,
                            a.palette.primary,
                            a.palette.secondary,
                          ], stops: const [0, 0.6, 0.6]),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(a.palette.name, style: value),
                    ],
                  ),
                  onTap: () => _open(const AppearanceScreen()),
                ),
              ]),
            ),
            const SizedBox(height: 32),
            AboutSection(),
            const SizedBox(height: 32),
            DangerSection(onDeleted: _onDataChanged),
          ],
          ),
        ),
      ),
    );
  }
}
