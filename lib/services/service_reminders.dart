import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../db/database_helper.dart';
import '../models/service_record.dart';
import '../utils/service_schedule.dart';

/// Phone notifications for service schedules: one at 09:00 on a due date,
/// and one when a fill-up's odometer comes within 100 km of a due km.
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

  Future<void> _init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
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
      for (final v in await db.getVehicles()) {
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
      }
      if (ask) await askPermission();
    } catch (e) {
      debugPrint('Service reminders failed: $e');
    }
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
    } catch (e) {
      debugPrint('Km reminder failed: $e');
    }
  }
}
