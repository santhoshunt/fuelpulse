import 'dart:io';

import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/database_helper.dart';
import '../screens/service_screen.dart' show latestOdometer;
import 'trip_calculator.dart';

/// Shares every vehicle's trips as one CSV: when, where on the odometer,
/// how far, and the fuel and its cost worked out the same way as the trip
/// page. Returns how many trips were written.
Future<int> exportTripsCsv() async {
  final db = DatabaseHelper();
  final rows = <List<Object?>>[
    [
      'vehicle',
      'trip',
      'start',
      'end',
      'startOdometer',
      'endOdometer',
      'km',
      'fuelLitres',
      'fuelFigure',
      'fuelCost',
      'kmPerLitre',
      'notes',
    ],
  ];
  for (final v in await db.getVehicles()) {
    final chrono = await db.getAllLogsChrono(v.id);
    final avg = averageKmL(chrono);
    final latest = await latestOdometer(v.id);
    for (final t in (await db.getTrips(v.id)).reversed) {
      final end = t.endOdometer ?? latest ?? t.startOdometer;
      final f = tripFuel(t, chrono, endOdometer: end, averageKmL: avg);
      rows.add([
        v.name,
        t.name,
        t.startAt,
        t.endAt ?? '',
        t.startOdometer,
        t.endOdometer ?? '',
        end - t.startOdometer,
        f == null ? '' : f.litres.toStringAsFixed(2),
        f?.quality.name ?? '',
        f?.cost == null ? '' : f!.cost!.toStringAsFixed(2),
        f?.kmPerLitre == null ? '' : f!.kmPerLitre!.toStringAsFixed(2),
        t.notes,
      ]);
    }
  }
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/my_hness_trips.csv');
  await file.writeAsString(const ListToCsvConverter().convert(rows));
  await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path)], subject: "My H'ness trips"));
  return rows.length - 1;
}
