import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import '../db/database_helper.dart';
import '../services/drive_backup_service.dart';
import '../services/home_widgets.dart';
import '../services/service_reminders.dart';
import '../services/update_downloader.dart';
import '../services/update_installer.dart';
import '../services/update_prefs.dart';
import '../services/update_service.dart';
import '../utils/odometer_reading.dart';
import '../utils/page_routes.dart';
import '../utils/vehicle_manager.dart';
import '../widgets/update_banner.dart';
import 'analytics_screen.dart';
import 'dashboard_screen.dart';
import 'entry_form_screen.dart';
import 'fuel_list_screen.dart';
import 'garage_screen.dart';
import 'scan_photos_screen.dart';
import 'trip_screen.dart';
import 'trip_sheets.dart';
import 'settings_screen.dart';

/// The app's root: one tab per area over an [IndexedStack], so each tab
/// keeps its scroll position. Start-up work that belongs to the app rather
/// than to one screen (scheduled Drive backup, update check) runs here.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  /// Bumped whenever stored data may have changed (a tab switch, a save in
  /// another tab). Tabs that show stored data listen and read it again.
  final _reload = ValueNotifier<int>(0);
  int _tab = 0;

  /// Runs once per tab switch, as a fade-through on a shared axis: the old
  /// tab drifts towards the side you left and fades out, then the new one
  /// drifts in from the side you moved towards as it fades in.
  late final _tabIn = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 300), value: 1);

  /// The tab being left, and 1 when the new one is to its right, else -1.
  int _from = 0;
  int _dir = 1;

  /// The Garage tab's list: 0 Service, 1 Trips, 2 Papers.
  final _garageSection = ValueNotifier<int>(0);

  StreamSubscription<Uri?>? _widgetTaps;
  StreamSubscription<Uri>? _notificationTaps;

  @override
  void initState() {
    super.initState();
    if (HomeWidgets.supported) {
      // The home screen widgets show what the app holds; keep them current.
      _reload.addListener(HomeWidgets.refresh);
      unawaited(HomeWidgets.refresh());
      _widgetTaps = HomeWidget.widgetClicked.listen(_openFromWidget);
      HomeWidget.initiallyLaunchedFromHomeWidget().then(_openFromWidget);
    }
    // Scheduled Drive backup, fire-and-forget so it never blocks startup;
    // failures surface in Settings via DriveBackupService.lastError().
    // google_sign_in 6.x only has an Android implementation here.
    if (!kIsWeb && Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(DriveBackupService().checkAndRunScheduled());
        // Restores and edits change schedules; rebuild the reminders.
        unawaited(ServiceReminders.instance.rescheduleAll());
        unawaited(_restoreTripNotifications());
      });
      // Taps on the trip notification and its buttons open like widget links.
      _notificationTaps =
          ServiceReminders.instance.taps.stream.listen(_openFromWidget);
      ServiceReminders.instance.launchUri().then(_openFromWidget);
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

  /// A phone may drop an ongoing notification (battery saver, a restart);
  /// put back the one for every trip still on.
  Future<void> _restoreTripNotifications() async {
    for (final v in await DatabaseHelper().getVehicles()) {
      await refreshTripNotification(v.id);
    }
  }

  /// A widget or notification tap's fuelpulse:// link: a tab, or a form or
  /// page opened over it.
  Future<void> _openFromWidget(Uri? uri) async {
    if (uri == null || !mounted) return;
    const tabs = {'dashboard': 0, 'fuel': 1, 'service': 2, 'analytics': 3};
    final tab = tabs[uri.host];
    if (tab != null) {
      if (uri.host == 'service') _garageSection.value = 0;
      _select(tab);
      return;
    }
    if (uri.host == 'trips') {
      _garageSection.value = 1;
      _select(2);
      return;
    }
    // A trip notification's link names the trip's vehicle (?v=id).
    final named = uri.queryParameters['v'];
    final v = (named == null ? null : await DatabaseHelper().getVehicle(named)) ??
        await loadActiveVehicle();
    if (!mounted) return;
    switch (uri.host) {
      case 'add':
        await Navigator.push(
            context, SmoothPageRoute(page: EntryFormScreen(vehicleId: v.id)));
      case 'scan':
        final last = await DatabaseHelper().getLastLog(v.id);
        if (!mounted) return;
        final outcome = await Navigator.push<ScanOutcome>(context,
            SmoothPageRoute(page: ScanPhotosScreen(lastOdometer: last?.odometer)));
        if (outcome == null || !mounted) return;
        await Navigator.push(
            context,
            SmoothPageRoute(
                page: EntryFormScreen(
                    vehicleId: v.id,
                    prefill: outcome.isEmpty ? null : outcome)));
      case 'odometer':
        await showOdometerDialog(context,
            vehicleId: v.id,
            vehicleName: v.name,
            scanFirst: uri.queryParameters['photo'] == '1');
      case 'trip':
        final t = await DatabaseHelper().activeTrip(v.id);
        if (t == null || !mounted) break;
        await Navigator.push(
            context, SmoothPageRoute(page: TripScreen(tripId: t.id)));
      case 'starttrip':
        final on = await DatabaseHelper().activeTrip(v.id);
        if (!mounted) break;
        if (on != null) {
          await Navigator.push(
              context, SmoothPageRoute(page: TripScreen(tripId: on.id)));
        } else {
          await showStartTripSheet(context, v);
        }
      case 'endtrip':
        final t = await DatabaseHelper().activeTrip(v.id);
        if (t == null || !mounted) break;
        await showEndTripSheet(context, t, v);
    }
    await refreshTripNotification(v.id);
    _reload.value++;
  }

  @override
  void dispose() {
    _widgetTaps?.cancel();
    _notificationTaps?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _reload.dispose();
    _garageSection.dispose();
    _tabIn.dispose();
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
          "for My H'ness again."),
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
        label: 'Settings',
        onPressed: ChannelUpdateInstaller.instance.openInstallSettings,
      ),
    ));
  }

  void _select(int i) {
    if (i == _tab) return;
    _from = _tab;
    _dir = i > _tab ? 1 : -1;
    setState(() => _tab = i);
    _tabIn.forward(from: 0);
    // The tab coming into view may show data another tab just changed.
    _reload.value++;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: AnimatedBuilder(
              animation: _tabIn,
              builder: (context, _) {
                // The first 30% takes the old tab out; the rest brings the
                // new one in. The stack swaps tabs at the split, so a tab
                // keeps its state and only one shows at a time.
                const split = 0.3;
                final t = _tabIn.value;
                final leaving = t < split;
                final p = leaving ? t / split : (t - split) / (1 - split);
                final opacity = leaving
                    ? 1 - Curves.easeIn.transform(p)
                    : Curves.easeOut.transform(p);
                final dx = leaving
                    ? -_dir * 30 * Curves.easeIn.transform(p)
                    : _dir * 30 * (1 - Curves.easeOutCubic.transform(p));
                return Opacity(
                  opacity: opacity.clamp(0.0, 1.0),
                  child: Transform.translate(
                    offset: Offset(dx, 0),
                    child: IndexedStack(
                      index: leaving ? _from : _tab,
                      children: [
                        DashboardScreen(reload: _reload),
                        FuelListScreen(reload: _reload),
                        GarageScreen(
                            reload: _reload, section: _garageSection),
                        AnalyticsScreen(reload: _reload),
                        const SettingsScreen(),
                      ],
                    ),
                  ),
                );
              },
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
              icon: Icon(Icons.garage_outlined),
              selectedIcon: Icon(Icons.garage),
              label: 'Garage'),
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
