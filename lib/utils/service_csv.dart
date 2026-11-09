import 'dart:io';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart' show DateFormat;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/database_helper.dart';
import '../models/service_record.dart';
import '../models/service_type.dart';
import '../models/workshop.dart';
import '../services/service_reminders.dart';
import '../services/app_lock.dart';

/// Columns of a service CSV, in order. `types` is a `|`-separated list of
/// service type names; `workshop` is a workshop name. Both are created when
/// missing. Dates are ISO (2026-07-10 or 2026-07-10T10:00).
const kServiceCsvHeaders = [
  'id',
  'timestamp',
  'odometer',
  'workshop',
  'types',
  'cost',
  'notes',
  'nextDueKm',
  'nextDueDate',
];

/// Shares a CSV with only the header row, to fill in a spreadsheet.
Future<void> exportServiceTemplate() async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/fuelpulse_services_template.csv');
  await file.writeAsString(const ListToCsvConverter().convert([kServiceCsvHeaders]));
  await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path)], subject: "My H'ness service template"));
}

/// Picks a CSV and adds its services to [vehicleId]. Returns how many were
/// imported, or null when the picker is cancelled.
Future<int?> importServicesCsv({required String vehicleId}) async {
  final picked = await withoutRelock(() =>
      FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['csv']));
  final path = picked?.path;
  if (path == null) return null;
  final content = (await File(path).readAsString()).replaceAll('\r\n', '\n');
  return importServiceRows(const CsvToListConverter(eol: '\n').convert(content),
      vehicleId: vehicleId);
}

/// The import itself, without the file picker. Rows without a readable
/// timestamp or odometer are skipped. A row with an existing id replaces it.
Future<int> importServiceRows(List<List<dynamic>> rows,
    {required String vehicleId}) async {
  if (rows.isEmpty) throw const FormatException('CSV file is empty');
  final headers = rows.first.map((h) => '$h'.trim().toLowerCase()).toList();
  int? col(String name) {
    final i = headers.indexOf(name.toLowerCase());
    return i < 0 ? null : i;
  }

  final tsCol = col('timestamp');
  final odoCol = col('odometer');
  if (tsCol == null || odoCol == null) {
    throw const FormatException('The CSV needs timestamp and odometer columns.');
  }
  final db = DatabaseHelper();
  final workshops = {
    for (final w in await db.getWorkshops()) w.name.toLowerCase(): w.id,
  };
  final types = {
    for (final t in await db.getServiceTypes()) t.name.toLowerCase(): t.id,
  };
  var typeOrder = types.length;

  String cell(List<dynamic> row, int? i) =>
      i == null || i >= row.length ? '' : '${row[i]}'.trim();

  var count = 0;
  for (var r = 1; r < rows.length; r++) {
    final row = rows[r];
    final at = DateTime.tryParse(cell(row, tsCol));
    final odo = num.tryParse(cell(row, odoCol))?.toInt();
    if (at == null || odo == null) continue;

    String? workshopId;
    final wName = cell(row, col('workshop'));
    if (wName.isNotEmpty) {
      workshopId = workshops[wName.toLowerCase()];
      if (workshopId == null) {
        workshopId = '${Workshop.generateId()}$r';
        await db.upsertWorkshop(Workshop(id: workshopId, name: wName));
        workshops[wName.toLowerCase()] = workshopId;
      }
    }

    final typeIds = <String>[];
    for (final name in cell(row, col('types')).split('|')) {
      final n = name.trim();
      if (n.isEmpty) continue;
      var id = types[n.toLowerCase()];
      if (id == null) {
        id = '${ServiceType.generateId()}$r${typeIds.length}';
        await db.upsertServiceType(
            ServiceType(id: id, name: n, sortOrder: typeOrder++));
        types[n.toLowerCase()] = id;
      }
      typeIds.add(id);
    }

    final due = DateTime.tryParse(cell(row, col('nextDueDate')));
    final id = cell(row, col('id'));
    await db.insertService(ServiceRecord(
      id: id.isEmpty ? '${ServiceRecord.generateId()}$r' : id,
      vehicleId: vehicleId,
      timestamp: at.toIso8601String(),
      odometer: odo,
      workshopId: workshopId,
      typeIds: typeIds,
      cost: double.tryParse(cell(row, col('cost'))),
      notes: cell(row, col('notes')),
      nextDueKm: num.tryParse(cell(row, col('nextDueKm')))?.toInt(),
      nextDueDate: due == null ? null : DateFormat('yyyy-MM-dd').format(due),
    ));
    count++;
  }
  await ServiceReminders.instance.rescheduleAll();
  return count;
}
