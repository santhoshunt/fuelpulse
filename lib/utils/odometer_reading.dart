import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show ImageSource;
import 'package:intl/intl.dart' show NumberFormat;
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../screens/readings_screen.dart';
import '../screens/scan_photos_screen.dart' show photoScanSupported;
import 'page_routes.dart';
import '../services/photo_scan.dart' show scanOdometer;
import '../services/service_reminders.dart';

/// The latest odometer you entered outside a fill-up, per vehicle. It feeds
/// today's tank estimate and the km left to a service; it is not a fill-up.
typedef OdometerReading = ({int km, DateTime at});

/// One entry in a vehicle's readings, with how it was entered: 'typed',
/// 'photo', 'notification', 'trip start' or 'trip end'.
typedef LoggedReading = ({int km, DateTime at, String how});

/// Before 4.4 only the latest reading was kept, under this key.
String _oldKey(String vehicleId) => 'fuel_odometer_reading_$vehicleId';
String _key(String vehicleId) => 'fuel_odometer_readings_$vehicleId';

/// Readings kept per vehicle; older ones drop off.
const _keep = 200;

/// Every reading for [vehicleId], newest first.
Future<List<LoggedReading>> loadReadings(String vehicleId) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_key(vehicleId));
  final out = <LoggedReading>[];
  try {
    if (raw != null) {
      for (final m in (jsonDecode(raw) as List).cast<Map<String, dynamic>>()) {
        out.add((
          km: (m['km'] as num).toInt(),
          at: DateTime.parse(m['at'] as String),
          how: m['how'] as String? ?? 'typed',
        ));
      }
    } else {
      final old = prefs.getString(_oldKey(vehicleId));
      if (old != null) {
        final m = jsonDecode(old) as Map<String, dynamic>;
        out.add((
          km: (m['km'] as num).toInt(),
          at: DateTime.parse(m['at'] as String),
          how: 'typed',
        ));
      }
    }
  } catch (_) {
    // A damaged list reads as empty rather than stopping the app.
  }
  out.sort((a, b) => b.at.compareTo(a.at));
  return out;
}

Future<void> _storeReadings(String vehicleId, List<LoggedReading> list) async {
  final prefs = await SharedPreferences.getInstance();
  list.sort((a, b) => b.at.compareTo(a.at));
  await prefs.setString(
      _key(vehicleId),
      jsonEncode([
        for (final r in list.take(_keep))
          {'km': r.km, 'at': r.at.toIso8601String(), 'how': r.how},
      ]));
  await prefs.remove(_oldKey(vehicleId));
}

/// The current reading: the newest one, or null. A reading below the last
/// fill-up's odometer is stale (a fill-up came after it) and is ignored.
Future<OdometerReading?> loadReading(String vehicleId) async {
  final r = (await loadReadings(vehicleId)).firstOrNull;
  if (r == null) return null;
  final last = await DatabaseHelper().getLastLog(vehicleId);
  return last != null && r.km < last.odometer ? null : (km: r.km, at: r.at);
}

/// Removes one reading; the one before it becomes current.
Future<void> deleteReading(String vehicleId, DateTime at) async {
  final list = await loadReadings(vehicleId)
    ..removeWhere((r) => r.at == at);
  await _storeReadings(vehicleId, list);
  await ServiceReminders.instance.rescheduleAll();
}

/// Puts back a reading removed with [deleteReading].
Future<void> restoreReading(String vehicleId, LoggedReading r) async {
  final list = await loadReadings(vehicleId)
    ..removeWhere((e) => e.at == r.at)
    ..add(r);
  await _storeReadings(vehicleId, list);
  await ServiceReminders.instance.rescheduleAll();
}

/// Litres left now: the level right after the last refill, less what the
/// km driven since burned at [avgKmL]. Null without a reading or average.
double? tankNow({
  required double afterRefill,
  required int refillOdometer,
  required OdometerReading? reading,
  required double? avgKmL,
}) {
  if (reading == null || avgKmL == null || avgKmL <= 0) return null;
  return (afterRefill - (reading.km - refillOdometer) / avgKmL)
      .clamp(0.0, afterRefill);
}

/// Adds a reading as the current one, [how] saying where it came from.
/// Returns its time, which [deleteReading] takes to undo it.
Future<DateTime> saveReading(String vehicleId, int km,
    {String how = 'typed'}) async {
  final at = DateTime.now();
  await _storeReadings(
      vehicleId, [(km: km, at: at, how: how), ...await loadReadings(vehicleId)]);
  await ServiceReminders.instance.checkKmDue(vehicleId, km);
  await ServiceReminders.instance.checkLowFuel(vehicleId, km);
  // Moves the weekly reading reminder past this reading.
  await ServiceReminders.instance.rescheduleAll();
  return at;
}

/// How a reading was entered, for the Readings page.
String readingSourceLabel(String how) => switch (how) {
      'photo' => 'from a photo',
      'notification' => 'from the notification',
      'trip start' => 'at a trip start',
      'trip end' => 'at a trip end',
      _ => 'typed',
    };

/// Saves a reading typed as text, such as "23,456" or "23456 km", from the
/// reminder's reply box. Uses the same checks as the reading dialog.
/// Returns the km saved, or why it was not.
Future<({int? km, String? error})> saveTypedReading(
    String vehicleId, String? text) async {
  final digits =
      RegExp(r'\d[\d, ]*').firstMatch(text ?? '')?.group(0)?.replaceAll(RegExp(r'[, ]'), '');
  final km = int.tryParse(digits ?? '');
  if (km == null) {
    return (km: null, error: 'Type the reading in km, like 23456.');
  }
  final last = await DatabaseHelper().getLastLog(vehicleId);
  if (last != null && km < last.odometer) {
    return (
      km: null,
      error: '$km km is lower than the last fill-up (${last.odometer} km). '
          'Type it again.'
    );
  }
  await saveReading(vehicleId, km, how: 'notification');
  return (km: km, error: null);
}

/// Asks whether to take a photo or pick one from the gallery, then reads
/// the odometer from it. Null when cancelled or unread.
Future<int?> pickOdometerPhoto(BuildContext context, int? last) async {
  final source = await showModalBottomSheet<ImageSource>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take a photo'),
            onTap: () => Navigator.pop(ctx, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('Choose from gallery'),
            onTap: () => Navigator.pop(ctx, ImageSource.gallery),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (source == null) return null;
  return scanOdometer(last, source: source);
}

/// What the dialog's All readings button returns instead of a reading.
const _openReadings = -1;

/// Asks for today's odometer. Returns true when a reading was saved. With
/// [scanFirst] (the Odometer widget's Photo button) the photo choice opens
/// first and its reading fills the field. A saved reading shows Undo;
/// [onChanged] runs after an Undo or after the Readings page closes, so the
/// caller can show the current reading again.
Future<bool> showOdometerDialog(BuildContext context,
    {required String vehicleId,
    required String vehicleName,
    bool scanFirst = false,
    VoidCallback? onChanged}) async {
  final last = await DatabaseHelper().getLastLog(vehicleId);
  final current = await loadReading(vehicleId);
  final scanned = scanFirst && photoScanSupported
      ? context.mounted
          ? await pickOdometerPhoto(context, current?.km ?? last?.odometer)
          : null
      : null;
  if (!context.mounted) return false;
  final controller = TextEditingController(
      text: (scanned ?? current?.km ?? last?.odometer)?.toString() ?? '');
  String? error = scanFirst && scanned == null && photoScanSupported
      ? "Couldn't read the odometer; type it in"
      : null;
  // The last value read from a photo, to tell a photo reading from a typed one.
  int? fromPhoto = scanned;
  final km = await showDialog<int>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialog) => AlertDialog(
        title: Text('Odometer · $vehicleName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Reading now',
                suffixText: 'km',
                errorText: error,
                suffixIcon: photoScanSupported
                    ? IconButton(
                        tooltip: 'Read it from a photo',
                        icon: const Icon(Icons.photo_camera_outlined),
                        onPressed: () async {
                          final v = await pickOdometerPhoto(
                              ctx, current?.km ?? last?.odometer);
                          setDialog(() {
                            if (v == null) {
                              error = "Couldn't read the odometer; type it in";
                            } else {
                              controller.text = '$v';
                              fromPhoto = v;
                              error = null;
                            }
                          });
                        },
                      )
                    : null,
              ),
            ),
            const SizedBox(height: 8),
            Text(
                last == null
                    ? 'Used for the tank estimate and service reminders.'
                    : 'Last fill-up at ${last.odometer} km. Used for the tank '
                        'estimate and service reminders; not saved as a fill-up.',
                style: Theme.of(ctx).textTheme.bodySmall),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, _openReadings),
              child: const Text('All readings')),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              final v = int.tryParse(controller.text.trim());
              if (v == null || v < 0) {
                setDialog(() => error = 'Enter the reading in km');
                return;
              }
              if (last != null && v < last.odometer) {
                setDialog(() =>
                    error = 'Lower than the last fill-up (${last.odometer} km)');
                return;
              }
              Navigator.pop(ctx, v);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  if (km == null || !context.mounted) return false;
  if (km == _openReadings) {
    await Navigator.push(
        context,
        SmoothPageRoute(
            page: ReadingsScreen(vehicleId: vehicleId, vehicleName: vehicleName)));
    onChanged?.call();
    return false;
  }
  final at = await saveReading(vehicleId, km,
      how: km == fromPhoto ? 'photo' : 'typed');
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Saved ${NumberFormat('#,##,##0', 'en_IN').format(km)} km'),
      persist: false,
      duration: const Duration(seconds: 6),
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () async {
          await deleteReading(vehicleId, at);
          onChanged?.call();
        },
      ),
    ));
  }
  return true;
}
