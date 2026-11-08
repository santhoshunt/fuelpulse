import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../services/service_reminders.dart';
import '../theme/app_colors.dart';
import '../utils/appearance_prefs.dart';
import '../utils/mileage_bands.dart';
import '../utils/page_routes.dart';
import '../utils/vehicle_manager.dart';
import 'appearance_screen.dart';
import 'import_export_screen.dart';
import 'mileage_ranges_screen.dart';
import 'pumps_screen.dart';
import 'service_types_screen.dart';
import 'workshops_screen.dart';
import 'settings/about_section.dart';
import 'settings/danger_section.dart';
import 'settings/settings_widgets.dart';
import 'settings/vehicles_section.dart';

export 'settings/restore_mode_dialog.dart' show showRestoreModeDialog;

/// The Settings tab: Vehicles inline; Lists, Data and Appearance as rows
/// that open their own pages; then About and Delete all data. Each section
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
  int _pumpCount = 0;
  int _workshopCount = 0;
  int _typeCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    final db = DatabaseHelper();
    final pumps = await db.getPumps();
    final workshops = await db.getWorkshops();
    final types = await db.getServiceTypes();
    if (!mounted) return;
    setState(() {
      _pumpCount = pumps.length;
      _workshopCount = workshops.length;
      _typeCount = types.length;
    });
  }

  /// A restore (Drive or backup file) or a data wipe changed what Settings
  /// shows. A merge can add vehicles; a replace also rewrites the
  /// appearance, fuel types and pump brands. Reload every section that
  /// mirrors them.
  Future<void> _onDataChanged({bool themeChanged = false}) async {
    if (themeChanged) await reloadAppearance();
    // A wipe removes services whose reminders are still set.
    await ServiceReminders.instance.rescheduleAll();
    if (!mounted) return;
    setState(() => _reloadToken++);
    await _loadCounts();
  }

  Future<void> _onRestored(bool replaced) =>
      _onDataChanged(themeChanged: replaced);

  /// Mileage or cost ranges for the active vehicle, saved on Done.
  Future<void> _ranges({required bool cost}) async {
    final v = await loadActiveVehicle();
    if (!mounted) return;
    final limits = await Navigator.push<List<double>>(
      context,
      SmoothPageRoute(
        page: MileageRangesScreen(
          vehicleName: v.name,
          type: v.type,
          cost: cost,
          limits: cost ? costBandsFor(v).limits : bandsFor(v).limits,
        ),
      ),
    );
    if (limits == null) return;
    await DatabaseHelper().updateVehicle(cost
        ? v.copyWith(costBands: limits)
        : v.copyWith(mileageBands: limits));
  }

  Future<void> _open(Widget page) async {
    await Navigator.push(context, SmoothPageRoute(page: page));
    await _loadCounts();
  }

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
            sectionHeader('Lists'),
            const SizedBox(height: 12),
            settingsGroup([
              SettingsRow(
                icon: Icons.local_gas_station_outlined,
                label: 'Petrol pumps',
                trailing: Text('$_pumpCount', style: value),
                onTap: () => _open(const PumpsScreen()),
              ),
              SettingsRow(
                icon: Icons.store_outlined,
                label: 'Workshops',
                trailing: Text('$_workshopCount', style: value),
                onTap: () => _open(const WorkshopsScreen()),
              ),
              SettingsRow(
                icon: Icons.build_outlined,
                label: 'Service types',
                trailing: Text('$_typeCount', style: value),
                onTap: () => _open(const ServiceTypesScreen()),
              ),
            ]),
            const SizedBox(height: 32),
            sectionHeader('Grading'),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: Text(
                  "For the active vehicle. A fill-up's grade is the lower of "
                  'its mileage and cost per km grades.',
                  style: TextStyle(color: colors.textSecondary, fontSize: 12)),
            ),
            settingsGroup([
              SettingsRow(
                icon: Icons.speed,
                label: 'Mileage ranges',
                onTap: () => _ranges(cost: false),
              ),
              SettingsRow(
                icon: Icons.currency_rupee,
                label: 'Cost per km ranges',
                onTap: () => _ranges(cost: true),
              ),
            ]),
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
