import 'dart:io';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/fuel_log.dart';

// ── CSV Export ────────────────────────────────────────────────────────

Future<void> exportCsv(List<FuelLog> logs) async {
  // Sort chronologically (oldest first)
  final sorted = List<FuelLog>.from(logs)
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  final rows = <List<dynamic>>[
    ['id', 'timestamp', 'odometer', 'liters', 'pumpBrand', 'fullTank', 'notes'],
    ...sorted.map((l) => [
          l.id,
          l.timestamp,
          l.odometer,
          l.liters,
          l.pumpBrand,
          l.fullTank ? 'true' : 'false',
          l.notes,
        ]),
  ];

  final csvString = const ListToCsvConverter().convert(rows);
  final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final fileName = 'fuelpulse_$dateStr.csv';

  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsString(csvString);

  await Share.shareXFiles(
    [XFile(file.path)],
    subject: 'FuelPulse Export',
  );
}

// ── CSV Import ────────────────────────────────────────────────────────

/// Parse a CSV file and return a list of FuelLog entries.
/// Returns null if the user cancels the file picker.
/// Throws on invalid CSV format (missing required columns).
Future<List<FuelLog>?> importCsv() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['csv'],
  );

  if (result == null || result.files.isEmpty) return null;
  final filePath = result.files.single.path;
  if (filePath == null) return null;

  final content = await File(filePath).readAsString();
  final rows = const CsvToListConverter(eol: '\n').convert(content);

  if (rows.isEmpty) throw FormatException('CSV file is empty');

  // Parse headers
  final headers =
      rows.first.map((h) => h.toString().toLowerCase().trim()).toList();

  int? findCol(List<String> aliases) {
    for (int i = 0; i < headers.length; i++) {
      for (final alias in aliases) {
        if (headers[i].contains(alias)) return i;
      }
    }
    return null;
  }

  final odoCol = findCol(['odometer', 'odo']);
  final litersCol = findCol(['liters', 'liter', 'litres', 'litre']);
  // Special handling: single 'l' must match exactly to avoid matching random words
  if (litersCol == null) {
    for (int i = 0; i < headers.length; i++) {
      if (headers[i] == 'l') {
        // found exact 'l' column
        return _parseRows(rows, odoCol, i,
            findCol(['brand', 'pump', 'pumpbrand', 'station']),
            findCol(['notes', 'note', 'comment', 'comments']),
            findCol(['fulltank', 'full_tank', 'full', 'tank_full']),
            findCol(['timestamp', 'date', 'time']));
      }
    }
  }

  if (odoCol == null || litersCol == null) {
    throw FormatException(
        'CSV must have at least "odometer" and "liters" columns');
  }

  final brandCol = findCol(['brand', 'pump', 'pumpbrand', 'station']);
  final notesCol = findCol(['notes', 'note', 'comment', 'comments']);
  final fullTankCol = findCol(['fulltank', 'full_tank', 'full', 'tank_full']);
  final timestampCol = findCol(['timestamp', 'date', 'time']);

  return _parseRows(
      rows, odoCol, litersCol, brandCol, notesCol, fullTankCol, timestampCol);
}

List<FuelLog> _parseRows(
  List<List<dynamic>> rows,
  int? odoCol,
  int? litersCol,
  int? brandCol,
  int? notesCol,
  int? fullTankCol,
  int? timestampCol,
) {
  if (odoCol == null || litersCol == null) {
    throw FormatException(
        'CSV must have at least "odometer" and "liters" columns');
  }

  final logs = <FuelLog>[];

  for (int r = 1; r < rows.length; r++) {
    final row = rows[r];
    if (row.length <= odoCol || row.length <= litersCol) continue;

    final odoVal = int.tryParse(row[odoCol].toString().trim());
    final litersVal = double.tryParse(row[litersCol].toString().trim());
    if (odoVal == null || litersVal == null) continue;

    String timestamp;
    if (timestampCol != null && row.length > timestampCol) {
      final ts = row[timestampCol].toString().trim();
      timestamp = ts.isNotEmpty ? ts : DateTime.now().toIso8601String();
    } else {
      timestamp = DateTime.now().toIso8601String();
    }

    String brand = '';
    if (brandCol != null && row.length > brandCol) {
      brand = row[brandCol].toString().trim();
    }

    String notes = '';
    if (notesCol != null && row.length > notesCol) {
      notes = row[notesCol].toString().trim();
    }

    bool fullTank = true;
    if (fullTankCol != null && row.length > fullTankCol) {
      final ft = row[fullTankCol].toString().toLowerCase().trim();
      fullTank = ft != 'false' && ft != '0' && ft != 'no';
    }

    logs.add(FuelLog(
      id: FuelLog.generateId(),
      timestamp: timestamp,
      odometer: odoVal,
      liters: litersVal,
      pumpBrand: brand,
      fullTank: fullTank,
      notes: notes,
    ));
  }

  return logs;
}
