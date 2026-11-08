import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database_helper.dart';
import '../services/service_reminders.dart';

/// The latest odometer you typed outside a fill-up, per vehicle. It feeds
/// today's tank estimate and the km left to a service; it is not a fill-up.
typedef OdometerReading = ({int km, DateTime at});

String _key(String vehicleId) => 'fuel_odometer_reading_$vehicleId';

/// The saved reading, or null. A reading below the last fill-up's odometer
/// is stale (a fill-up came after it) and is ignored.
Future<OdometerReading?> loadReading(String vehicleId) async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_key(vehicleId));
  if (raw == null) return null;
  try {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    final r = (km: (m['km'] as num).toInt(), at: DateTime.parse(m['at'] as String));
    final last = await DatabaseHelper().getLastLog(vehicleId);
    return last != null && r.km < last.odometer ? null : r;
  } catch (_) {
    return null;
  }
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

Future<void> saveReading(String vehicleId, int km) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_key(vehicleId),
      jsonEncode({'km': km, 'at': DateTime.now().toIso8601String()}));
  await ServiceReminders.instance.checkKmDue(vehicleId, km);
}

/// Asks for today's odometer. Returns true when a reading was saved.
Future<bool> showOdometerDialog(BuildContext context,
    {required String vehicleId, required String vehicleName}) async {
  final last = await DatabaseHelper().getLastLog(vehicleId);
  final current = await loadReading(vehicleId);
  if (!context.mounted) return false;
  final controller =
      TextEditingController(text: (current?.km ?? last?.odometer)?.toString() ?? '');
  String? error;
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
                  labelText: 'Reading now', suffixText: 'km', errorText: error),
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
  if (km == null) return false;
  await saveReading(vehicleId, km);
  return true;
}
