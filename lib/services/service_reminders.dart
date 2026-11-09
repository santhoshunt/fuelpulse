import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../db/database_helper.dart';
import '../models/service_record.dart';
import '../models/trip.dart';
import '../utils/service_schedule.dart';

/// Phone notifications for service schedules: one at 09:00 on a due date,
/// and one when a fill-up's odometer comes within 100 km of a due km. Also
/// paper renewals and part replacements, on their own channel.
/// Android only; elsewhere every call does nothing.
class ServiceReminders {
  ServiceReminders._();
  static final instance = ServiceReminders._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  static bool get supported => !kIsWeb && Platform.isAndroid;

  /// How close to a due km the km reminder fires.
  static const kmWarning = 100;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'service_reminders',
      'Service reminders',
      channelDescription: 'When a vehicle service is due',
    ),
  );

  static const _renewals = NotificationDetails(
    android: AndroidNotificationDetails(
      'renewals',
      'Renewals and parts',
      channelDescription:
          'When a paper needs renewing or a tyre or battery replacing',
    ),
  );

  static const _tripDetails = NotificationDetails(
    android: AndroidNotificationDetails(
      'trips',
      'Trip in progress',
      channelDescription: 'Stays while a trip is on, with quick buttons',
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      onlyAlertOnce: true,
      actions: [
        AndroidNotificationAction('add_fill_up', 'Add fill-up',
            showsUserInterface: true),
        AndroidNotificationAction('odometer', 'Odometer',
            showsUserInterface: true),
        AndroidNotificationAction('end_trip', 'End trip',
            showsUserInterface: true),
      ],
    ),
  );

  /// Taps on a notification or its buttons, as fuelpulse:// links that
  /// AppShell opens the same way as home screen widget links.
  final taps = StreamController<Uri>.broadcast();

  /// A button keeps the trip's vehicle (?v=id in the payload), so it acts
  /// on that vehicle even when another one is active in the app.
  static Uri? _linkFor(NotificationResponse r) {
    final payload = Uri.tryParse(r.payload ?? '');
    final v = payload?.queryParameters['v'];
    Uri link(String host) => Uri(
        scheme: 'fuelpulse',
        host: host,
        queryParameters: v == null ? null : {'v': v});
    switch (r.actionId) {
      case 'add_fill_up':
        return link('add');
      case 'odometer':
        return link('odometer');
      case 'end_trip':
        return link('endtrip');
    }
    return payload;
  }

  Future<void> _init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (r) {
        final link = _linkFor(r);
        if (link != null) taps.add(link);
      },
    );
    _ready = true;
  }

  /// The link of the notification that launched the app, or null.
  Future<Uri?> launchUri() async {
    if (!supported) return null;
    try {
      await _init();
      final d = await _plugin.getNotificationAppLaunchDetails();
      final r = d?.notificationResponse;
      if (d?.didNotificationLaunchApp != true || r == null) return null;
      return _linkFor(r);
    } catch (e) {
      debugPrint('Notification launch check failed: $e');
      return null;
    }
  }

  /// Shows, or refreshes, the notification that stays while [t] is on.
  Future<void> showTrip(Trip t, String vehicleName, int kmSoFar) async {
    if (!supported) return;
    try {
      await _init();
      final since = DateTime.tryParse(t.startAt);
      await _plugin.show(
        id: _id('trip${t.id}'),
        title: 'On a trip · ${t.name}',
        body: [
          '${NumberFormat('#,##,##0', 'en_IN').format(kmSoFar)} km so far',
          if (since != null) 'since ${DateFormat('E HH:mm').format(since)}',
          vehicleName,
        ].join(' · '),
        notificationDetails: _tripDetails,
        payload: 'fuelpulse://trip?v=${t.vehicleId}',
      );
    } catch (e) {
      debugPrint('Trip notification failed: $e');
    }
  }

  Future<void> cancelTrip(String tripId) async {
    if (!supported) return;
    try {
      await _init();
      await _plugin.cancel(id: _id('trip$tripId'));
    } catch (e) {
      debugPrint('Trip notification cancel failed: $e');
    }
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  /// False when the user turned notifications off for FuelPulse.
  Future<bool> enabled() async {
    if (!supported) return true;
    await _init();
    return await _android?.areNotificationsEnabled() ?? true;
  }

  /// Shows the system prompt (Android 13+) unless it was refused for good.
  Future<bool> askPermission() async {
    if (!supported) return true;
    await _init();
    return await _android?.requestNotificationsPermission() ?? true;
  }

  /// A notification id that stays the same for a service across runs
  /// (String.hashCode is not guaranteed to): FNV-1a, 30 bits.
  static int _id(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h = ((h ^ c) * 0x01000193) & 0xffffffff;
    }
    return h & 0x3fffffff;
  }

  Future<Map<String, String>> _typeNames() async => {
        for (final t in await DatabaseHelper().getServiceTypes()) t.id: t.name,
      };

  static String _names(ServiceRecord r, Map<String, String> types) {
    final names = [for (final id in r.typeIds) types[id] ?? 'Service'];
    return names.isEmpty ? 'Service' : names.join(', ');
  }

  /// Rebuilds every date reminder from the database: at launch, and after
  /// a service is saved or deleted, and after data is deleted or restored.
  /// With [ask], shows the permission prompt (once the user answered it,
  /// Android does not show it again).
  Future<void> rescheduleAll({bool ask = false}) async {
    if (!supported) return;
    try {
      await _init();
      await _plugin.cancelAllPendingNotifications();
      final db = DatabaseHelper();
      final types = await _typeNames();
      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      final vehicles = await db.getVehicles();
      for (final v in vehicles) {
        for (final r in openSchedules(await db.getServices(v.id))) {
          final due = DateTime.tryParse(r.nextDueDate ?? '');
          if (due == null) continue;
          final at = DateTime(due.year, due.month, due.day, 9);
          if (!at.isAfter(now)) continue;
          await _plugin.zonedSchedule(
            id: _id(r.id),
            // A fixed instant: no device time zone lookup needed.
            scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
            notificationDetails: _details,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            title: 'Service due today · ${v.name}',
            body: _names(r, types),
          );
        }
        for (final p in await db.getPapers(v.id)) {
          final exp = DateTime.tryParse(p.expiresOn ?? '');
          if (exp == null) continue;
          var at = DateTime(exp.year, exp.month, exp.day - p.remindDays, 9);
          if (!at.isAfter(now)) {
            // Added inside its reminder window: remind once, at the next
            // 09:00, unless it has already lapsed.
            final c = await _catchUp(prefs, 'fuel_paper_catchup_${p.id}_${p.expiresOn}', now, exp);
            if (c == null) continue;
            at = c;
          }
          await _plugin.zonedSchedule(
            id: _id('paper${p.id}'),
            scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
            notificationDetails: _renewals,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            title: '${p.displayName} renews on '
                '${DateFormat('d MMM').format(exp)} · ${v.name}',
            body: p.number.isEmpty
                ? 'Renew it before it lapses.'
                : '${p.number}: renew it before it lapses.',
          );
        }
        for (final p in await db.getParts(v.id)) {
          final due = p.dueDate;
          if (due == null) continue;
          var at = DateTime(due.year, due.month, due.day - 7, 9);
          if (!at.isAfter(now)) {
            final c = await _catchUp(
                prefs, 'fuel_part_catchup_${p.id}_${p.fittedAt}', now, due);
            if (c == null) continue;
            at = c;
          }
          await _plugin.zonedSchedule(
            id: _id('part${p.id}'),
            scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
            notificationDetails: _renewals,
            androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
            title: '${p.label} due for a change · ${v.name}',
            body: 'Fitted ${DateFormat('d MMM y').format(DateTime.parse(p.fittedAt))}, '
                'good for ${p.lifeMonths} months.',
          );
        }
      }
      // A trip notification can't be swiped away; take down any whose trip
      // has ended, or was deleted with its vehicle or by a restore.
      final live = <int>{};
      for (final v in vehicles) {
        final t = await db.activeTrip(v.id);
        if (t != null) live.add(_id('trip${t.id}'));
      }
      for (final n in await _plugin.getActiveNotifications()) {
        final id = n.id;
        if (n.channelId == 'trips' && id != null && !live.contains(id)) {
          await _plugin.cancel(id: id);
        }
      }
      if (ask) await askPermission();
    } catch (e) {
      debugPrint('Service reminders failed: $e');
    }
  }

  /// The one catch-up reminder for something first scheduled inside its
  /// reminder window: the next 09:00, kept under [key] so a later launch
  /// schedules the same one and not another. Null once it has fired, or
  /// when [deadline]'s day has passed.
  static Future<DateTime?> _catchUp(SharedPreferences prefs, String key,
      DateTime now, DateTime deadline) async {
    final stored = DateTime.tryParse(prefs.getString(key) ?? '');
    if (stored != null) return stored.isAfter(now) ? stored : null;
    if (DateTime(deadline.year, deadline.month, deadline.day + 1)
        .isBefore(now)) {
      return null;
    }
    final nine = DateTime(now.year, now.month, now.day, 9);
    final at = now.isBefore(nine) ? nine : nine.add(const Duration(days: 1));
    await prefs.setString(key, at.toIso8601String());
    return at;
  }

  /// After a fill-up: notifies once per service when [odometer] is within
  /// [kmWarning] of, or past, its due km.
  Future<void> checkKmDue(String vehicleId, int odometer) async {
    if (!supported) return;
    try {
      await _init();
      final db = DatabaseHelper();
      final vehicle = await db.getVehicle(vehicleId);
      final prefs = await SharedPreferences.getInstance();
      final types = await _typeNames();
      final km = NumberFormat('#,##,##0', 'en_IN');
      for (final r in openSchedules(await db.getServices(vehicleId))) {
        final due = r.nextDueKm;
        if (due == null || odometer < due - kmWarning) continue;
        // Per due km, so a rescheduled service reminds again.
        final key = 'fuel_km_reminded_${r.id}_$due';
        if (prefs.getBool(key) ?? false) continue;
        await _plugin.show(
          id: _id('km${r.id}'),
          title: 'Service due · ${vehicle?.name ?? 'your vehicle'}',
          body: '${_names(r, types)}: due at ${km.format(due)} km, '
              'now ${km.format(odometer)} km',
          notificationDetails: _details,
        );
        await prefs.setBool(key, true);
      }
      for (final p in await db.getParts(vehicleId)) {
        final life = p.lifeKm;
        if (life == null) continue;
        final due = p.fittedOdometer + life;
        if (odometer < due - kmWarning) continue;
        // Per fitting, so a replaced part reminds again.
        final key = 'fuel_part_reminded_${p.id}_${p.fittedOdometer}';
        if (prefs.getBool(key) ?? false) continue;
        await _plugin.show(
          id: _id('partkm${p.id}'),
          title: '${p.label} due for a change · ${vehicle?.name ?? 'your vehicle'}',
          body: 'Good for ${km.format(life)} km from ${km.format(p.fittedOdometer)}, '
              'now ${km.format(odometer)} km',
          notificationDetails: _renewals,
        );
        await prefs.setBool(key, true);
      }
    } catch (e) {
      debugPrint('Km reminder failed: $e');
    }
  }
}
