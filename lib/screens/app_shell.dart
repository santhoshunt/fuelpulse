import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../services/drive_backup_service.dart';
import '../services/service_reminders.dart';
import '../services/update_downloader.dart';
import '../services/update_installer.dart';
import '../services/update_prefs.dart';
import '../services/update_service.dart';
import '../widgets/update_banner.dart';
import 'analytics_screen.dart';
import 'dashboard_screen.dart';
import 'fuel_list_screen.dart';
import 'service_screen.dart';
import 'settings_screen.dart';

/// The app's root: one tab per area over an [IndexedStack], so each tab
/// keeps its scroll position. Start-up work that belongs to the app rather
/// than to one screen (scheduled Drive backup, update check) runs here.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  /// Bumped whenever stored data may have changed (a tab switch, a save in
  /// another tab). Tabs that show stored data listen and read it again.
  final _reload = ValueNotifier<int>(0);
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    // Scheduled Drive backup, fire-and-forget so it never blocks startup;
    // failures surface in Settings via DriveBackupService.lastError().
    // google_sign_in 6.x only has an Android implementation here.
    if (!kIsWeb && Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(DriveBackupService().checkAndRunScheduled());
        // Restores and edits change schedules; rebuild the reminders.
        unawaited(ServiceReminders.instance.rescheduleAll());
      });
    }
    if (_updatesSupported) {
      WidgetsBinding.instance.addObserver(this);
      // A downloaded update never outlives the launch after it.
      unawaited(UpdateDownloader().cleanup());
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _reportUpdateResult();
        _checkForUpdate();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _reload.dispose();
    super.dispose();
  }

  /// Android keeps the process in recents, so a launch is usually a resume:
  /// the daily check has to run there too.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkForUpdate();
  }

  static bool get _updatesSupported => !kIsWeb && Platform.isAndroid;

  bool _checkingForUpdate = false;

  /// When a launch check last failed (offline, rate limited). In memory
  /// only: a failure is retried after an hour, not on every resume.
  static DateTime? _updateCheckFailedAt;

  /// The daily launch check for a newer release (Settings can switch it
  /// off). Only reads GitHub; what it finds waits in [availableUpdate] for
  /// the banner, and no further check runs while it is there. Failures stay
  /// silent, since nobody asked. Ported from the expense tracker.
  Future<void> _checkForUpdate() async {
    if (!mounted || !_updatesSupported || _checkingForUpdate) return;
    if (availableUpdate.value != null) return;
    final now = DateTime.now();
    final failed = _updateCheckFailedAt;
    if (failed != null && now.difference(failed) < const Duration(hours: 1)) {
      return;
    }
    _checkingForUpdate = true;
    try {
      if (!shouldCheckForUpdate(
        enabled: await updateOnLaunch(),
        lastCheck: await updateLastCheck(),
        now: now,
      )) {
        return;
      }
      final result = await UpdateService().check();
      switch (result) {
        case UpdateAvailable(:final updates):
          availableUpdate.value = updates;
          await markUpdateChecked(now);
        case UpToDate():
          await markUpdateChecked(now);
        case CheckFailed():
          _updateCheckFailedAt = now;
      }
    } finally {
      _checkingForUpdate = false;
    }
  }

  /// First launch after an in-app update: say it worked, and point to the
  /// switch that allowed it, which the app cannot turn off itself.
  Future<void> _reportUpdateResult() async {
    if (!mounted || !_updatesSupported) return;
    final tag = await installingUpdateTag();
    if (tag == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final String version;
    try {
      version = await ChannelUpdateInstaller.instance.currentVersion();
    } catch (_) {
      return;
    }
    await setInstallingUpdateTag(null);
    if (UpdateService.compareVersions(version, tag) != 0) return;
    messenger.showSnackBar(SnackBar(
      content: Text('Updated to $tag. You can turn off Install unknown apps '
          'for FuelPulse again.'),
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
        label: 'Settings',
        onPressed: ChannelUpdateInstaller.instance.openInstallSettings,
      ),
    ));
  }

  void _select(int i) {
    if (i == _tab) return;
    setState(() => _tab = i);
    // The tab coming into view may show data another tab just changed.
    _reload.value++;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _tab,
              children: [
                DashboardScreen(reload: _reload),
                FuelListScreen(reload: _reload),
                ServiceScreen(reload: _reload),
                AnalyticsScreen(reload: _reload),
                const SettingsScreen(),
              ],
            ),
          ),
          const UpdateBanner(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.speed_outlined),
              selectedIcon: Icon(Icons.speed),
              label: 'Dashboard'),
          NavigationDestination(
              icon: Icon(Icons.local_gas_station_outlined),
              selectedIcon: Icon(Icons.local_gas_station),
              label: 'Fuel'),
          NavigationDestination(
              icon: Icon(Icons.build_outlined),
              selectedIcon: Icon(Icons.build),
              label: 'Service'),
          NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights),
              label: 'Analytics'),
          NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings),
              label: 'Settings'),
        ],
      ),
    );
  }
}
