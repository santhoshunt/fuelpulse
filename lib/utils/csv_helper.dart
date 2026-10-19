import 'dart:io';
import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/fuel_log.dart';

// ── CSV Export ────────────────────────────────────────────────────────

/// Build the CSV rows for a list of logs (header + data, oldest first).
/// Extracted from [exportCsv] so it can be tested without the share sheet.
List<List<dynamic>> buildCsvRows(List<FuelLog> logs) {
  final sorted = List<FuelLog>.from(logs)
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  return <List<dynamic>>[
    [
      'id',
      'timestamp',
      'odometer',
      'liters',
      'pumpBrand',
      'fullTank',
      'notes',
      // New columns appended so consumers of the old 7-column shape keep working.
      'fuelType',
      'pricePerLitre',
      'totalCost',
    ],
    ...sorted.map((l) => [
          l.id,
          l.timestamp,
          l.odometer,
          l.liters,
          l.pumpBrand,
          l.fullTank ? 'true' : 'false',
          l.notes,
          l.fuelType,
          l.pricePerLitre ?? '',
          l.totalCost ?? '',
        ]),
  ];
}

/// "Swift Dzire!" → "swift-dzire": the vehicle part of an export file name.
String vehicleSlug(String name) {
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'vehicle' : slug;
}

Future<void> exportCsv(List<FuelLog> logs, {required String vehicleName}) async {
  final csvString = const ListToCsvConverter().convert(buildCsvRows(logs));
  final dateStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
  final fileName = 'fuelpulse_${vehicleSlug(vehicleName)}_$dateStr.csv';

  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$fileName');
  await file.writeAsString(csvString);

  await SharePlus.instance.share(
    ShareParams(files: [XFile(file.path)], subject: 'FuelPulse Export'),
  );
}

// ── CSV Import ────────────────────────────────────────────────────────

/// Parse a CSV file and return a list of FuelLog entries.
/// Returns null if the user cancels the file picker.
/// Throws on invalid CSV format (missing required columns).
Future<List<FuelLog>?> importCsv({required String vehicleId}) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['csv'],
  );

  if (result == null || result.files.isEmpty) return null;
  final filePath = result.files.single.path;
  if (filePath == null) return null;

  final content = await File(filePath).readAsString();
  final rows = const CsvToListConverter(eol: '\n').convert(content);

  return parseCsvRows(rows, vehicleId: vehicleId);
}

/// Resolve columns and parse data rows. Extracted from [importCsv] so it can
/// be tested without the file picker. Header matching is tolerant: exact
/// match wins, then substring; a column claimed by an earlier lookup is
/// never matched again (so "pricePerLitre" cannot steal the litres lookup,
/// and "totalCost" cannot double-match as a price column).
/// Every parsed log is assigned to [vehicleId]: CSV carries no vehicle.
List<FuelLog> parseCsvRows(List<List<dynamic>> rows,
    {required String vehicleId}) {
  if (rows.isEmpty) throw FormatException('CSV file is empty');

  final headers =
      rows.first.map((h) => h.toString().toLowerCase().trim()).toList();
  final claimed = <int>{};

  int? findCol(List<String> aliases) {
    // Exact match first — our own exports always resolve here.
    for (int i = 0; i < headers.length; i++) {
      if (claimed.contains(i)) continue;
      for (final alias in aliases) {
        if (headers[i] == alias) {
          claimed.add(i);
          return i;
        }
      }
    }
    // Substring fallback for third-party headers.
    for (int i = 0; i < headers.length; i++) {
      if (claimed.contains(i)) continue;
      for (final alias in aliases) {
        if (headers[i].contains(alias)) {
          claimed.add(i);
          return i;
        }
      }
    }
    return null;
  }

  final odoCol = findCol(['odometer', 'odo']);
  var litersCol = findCol(['liters', 'liter', 'litres', 'litre']);
  // Special handling: single 'l' must match exactly to avoid matching random words
  if (litersCol == null) {
    for (int i = 0; i < headers.length; i++) {
      if (!claimed.contains(i) && headers[i] == 'l') {
        claimed.add(i);
        litersCol = i;
        break;
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
  final fuelTypeCol = findCol(['fueltype', 'fuel_type', 'fuel']);
  // totalCost resolves BEFORE price so "totalcost" can't be taken as a price.
  final totalCostCol = findCol(['totalcost', 'total_cost', 'cost', 'amount']);
  final priceCol = findCol(['priceperlitre', 'price_per_litre', 'price', 'rate']);

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

    String fuelType = 'Normal';
    if (fuelTypeCol != null && row.length > fuelTypeCol) {
      final v = row[fuelTypeCol].toString().trim();
      if (v.isNotEmpty) fuelType = v;
    }

    double? totalCost;
    if (totalCostCol != null && row.length > totalCostCol) {
      totalCost = double.tryParse(row[totalCostCol].toString().trim());
    }

    double? pricePerLitre;
    if (priceCol != null && row.length > priceCol) {
      pricePerLitre = double.tryParse(row[priceCol].toString().trim());
    }

    logs.add(FuelLog(
      vehicleId: vehicleId,
      id: FuelLog.generateId(),
      timestamp: timestamp,
      odometer: odoVal,
      liters: litersVal,
      pumpBrand: brand,
      fullTank: fullTank,
      notes: notes,
      fuelType: fuelType,
      totalCost: totalCost,
      pricePerLitre: pricePerLitre,
    ));
  }

  return logs;
}
