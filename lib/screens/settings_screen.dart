import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import '../services/app_lock.dart';
import '../services/service_reminders.dart';
import '../theme/app_colors.dart';
import '../utils/appearance_prefs.dart';
import '../utils/constants.dart';
import '../utils/mileage_bands.dart';
import '../utils/page_routes.dart';
import '../utils/vehicle_manager.dart';
import '../widgets/option_picker.dart';
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
  int _alertPercent = kMileageAlertDefault;
  int _lowFuelKm = kLowFuelKmDefault;
  String _readingReminder = kReadingReminderDefault;
  bool _lockOn = false;
  int _lockAfter = kAppLockAfterDefault;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    final db = DatabaseHelper();
    final pumps = await db.getPumps();
    final workshops = await db.getWorkshops();
    final prefs = await SharedPreferences.getInstance();
    final alert = prefs.getInt(kMileageAlertKey) ?? kMileageAlertDefault;
    final lowFuel = prefs.getInt(kLowFuelKmKey) ?? kLowFuelKmDefault;
    final reading =
        prefs.getString(kReadingReminderKey) ?? kReadingReminderDefault;
    final types = await db.getServiceTypes();
    if (!mounted) return;
    setState(() {
      _pumpCount = pumps.length;
      _workshopCount = workshops.length;
      _typeCount = types.length;
      _alertPercent = alert;
      _lowFuelKm = lowFuel;
      _readingReminder = reading;
      _lockOn = prefs.getBool(kAppLockKey) ?? false;
      _lockAfter = prefs.getInt(kAppLockAfterKey) ?? kAppLockAfterDefault;
    });
  }

  /// How far below average a tank's km/L must be to raise the Dashboard
  /// alert; 0 turns it off.
  Future<void> _pickAlert() async {
    final r = await showOptionPicker<int>(
      context: context,
      title: 'Mileage drop alert',
      options: [
        for (final p in const [0, 10, 15, 20, 25])
          PickerOption(
              value: p, label: p == 0 ? 'Off' : '$p% below average'),
      ],
      selected: _alertPercent,
    );
    if (r is! PickerPicked<int>) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kMileageAlertKey, r.value);
    if (mounted) setState(() => _alertPercent = r.value);
  }

  /// Turning the lock on asks to unlock once, so a phone without a
  /// working fingerprint or PIN can't lock you out.
  Future<void> _toggleLock(bool on) async {
    if (on) {
      if (!await canLock()) {
        if (mounted) {
          showSettingsSnack(
              context, 'Set a screen lock on your phone first.');
        }
        return;
      }
      if (!await authenticate('Turn on app lock')) return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kAppLockKey, on);
    if (mounted) setState(() => _lockOn = on);
  }

  String get _lockAfterLabel => switch (_lockAfter) {
        0 => 'Immediately',
        60 => 'After 1 minute',
        _ => 'After ${_lockAfter ~/ 60} minutes',
      };

  Future<void> _pickLockAfter() async {
    final r = await showOptionPicker<int>(
      context: context,
      title: 'Lock again',
      options: const [
        PickerOption(value: 0, label: 'Immediately'),
        PickerOption(value: 60, label: 'After 1 minute away'),
        PickerOption(value: 300, label: 'After 5 minutes away'),
      ],
      selected: _lockAfter,
    );
    if (r is! PickerPicked<int>) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kAppLockAfterKey, r.value);
    if (mounted) setState(() => _lockAfter = r.value);
  }

  static const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday',
      'Friday', 'Saturday', 'Sunday'];

  /// 'Sun 19:00', or 'Off'.
  String get _readingLabel {
    final parts = _readingReminder.split('|');
    final day = parts.length == 2 ? int.tryParse(parts[0]) : null;
    if (day == null || day < 1 || day > 7) return 'Off';
    return '${_days[day - 1].substring(0, 3)} ${parts[1]}';
  }

  /// A day of the week and a time, or Off, for the reading reminder.
  Future<void> _pickReadingReminder() async {
    final r = await showOptionPicker<int>(
      context: context,
      title: 'Odometer reading reminder',
      options: [
        const PickerOption(value: 0, label: 'Off'),
        for (var d = 1; d <= 7; d++)
          PickerOption(value: d, label: 'Every ${_days[d - 1]}'),
      ],
      selected: int.tryParse(_readingReminder.split('|').first) ?? 0,
    );
    if (r is! PickerPicked<int> || !mounted) return;
    var setting = 'off';
    if (r.value != 0) {
      final hm = _readingReminder.contains('|')
          ? _readingReminder.split('|')[1].split(':')
          : const ['19', '00'];
      final time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(
            hour: int.tryParse(hm[0]) ?? 19,
            minute: int.tryParse(hm.length > 1 ? hm[1] : '0') ?? 0),
      );
      if (time == null) return;
      setting = '${r.value}|${time.hour.toString().padLeft(2, '0')}:'
          '${time.minute.toString().padLeft(2, '0')}';
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kReadingReminderKey, setting);
    if (mounted) setState(() => _readingReminder = setting);
    await ServiceReminders.instance.rescheduleAll(ask: setting != 'off');
  }

  /// The range left at which an odometer reading warns of low fuel; 0 is
  /// off.
  Future<void> _pickLowFuel() async {
    final r = await showOptionPicker<int>(
      context: context,
      title: 'Low fuel warning',
      options: [
        for (final km in const [0, 30, 50, 100])
          PickerOption(
              value: km, label: km == 0 ? 'Off' : 'Under $km km left'),
      ],
      selected: _lowFuelKm,
    );
    if (r is! PickerPicked<int>) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(kLowFuelKmKey, r.value);
    if (mounted) setState(() => _lowFuelKm = r.value);
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
          vehicleId: v.id,
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
              SettingsRow(
                icon: Icons.trending_down,
                label: 'Mileage drop alert',
                trailing: Text(
                    _alertPercent == 0 ? 'Off' : '$_alertPercent%',
                    style: value),
                onTap: _pickAlert,
              ),
              SettingsRow(
                icon: Icons.local_gas_station_outlined,
                label: 'Low fuel warning',
                trailing: Text(_lowFuelKm == 0 ? 'Off' : '$_lowFuelKm km',
                    style: value),
                onTap: _pickLowFuel,
              ),
            ]),
            const SizedBox(height: 32),
            sectionHeader('Reminders'),
            const SizedBox(height: 12),
            settingsGroup([
              SettingsRow(
                icon: Icons.event_repeat,
                label: 'Odometer reading reminder',
                trailing: Text(_readingLabel, style: value),
                onTap: _pickReadingReminder,
              ),
            ]),
            if (appLockSupported) ...[
              const SizedBox(height: 32),
              sectionHeader('Security'),
              const SizedBox(height: 12),
              settingsGroup([
                SettingsRow(
                  icon: Icons.lock_outline,
                  label: 'App lock',
                  trailing: Switch(value: _lockOn, onChanged: _toggleLock),
                  onTap: () => _toggleLock(!_lockOn),
                ),
                if (_lockOn)
                  SettingsRow(
                    icon: Icons.timer_outlined,
                    label: 'Lock again',
                    trailing: Text(_lockAfterLabel, style: value),
                    onTap: _pickLockAfter,
                  ),
              ]),
            ],
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
