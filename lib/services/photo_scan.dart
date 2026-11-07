import 'dart:io';
import 'dart:math';
import 'dart:ui' show Rect;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:share_plus/share_plus.dart';

/// Reads an odometer photo or a fuel pump display photo on the phone with
/// ML Kit text recognition, so the fill-up form can pre-fill itself.
/// Nothing leaves the device unless the user shares a scan report.

enum ScanKind { odometer, pump }

/// One line of recognised text and where it sat in the photo.
class ScanLine {
  final String text;
  final Rect box;
  const ScanLine(this.text, this.box);
}

/// What the odometer photo gave. [value] is null when no number was found.
class OdometerRead {
  final int? value;

  /// TOTAL / ODO / TRIP A … as printed, or null when no label was found.
  final String? label;
  final List<int> candidates;

  const OdometerRead({this.value, this.label, this.candidates = const []});

  /// A TRIP reading counts km since the last fill-up, not the odometer.
  bool get isTrip => label?.startsWith('TRIP') ?? false;
}

/// What the pump photo gave. The three values are null unless they agree:
/// litres × rate must come within about ₹1 of the amount.
class PumpRead {
  final double? amount;
  final double? litres;
  final double? rate;
  final double? error;
  final List<double> numbers;

  const PumpRead(
      {this.amount, this.litres, this.rate, this.error, this.numbers = const []});

  bool get found => amount != null;
}

final _labelPattern =
    RegExp(r'\b(TOTAL|ODO|TRIP\s*[AB12])\b', caseSensitive: false);

/// Letters that segment and stylised digits are misread as, e.g. the 1 in a
/// real odometer read as "5 i98".
const _lookalikeDigits = {
  'O': '0', 'o': '0', 'D': '0', 'Q': '0',
  'I': '1', 'i': '1', 'l': '1', '|': '1', '!': '1',
  'Z': '2', 'z': '2',
  'S': '5', 's': '5',
  'G': '6', 'b': '6',
  'B': '8',
  'g': '9', 'q': '9',
};

/// Maps look-alike letters to digits, but only inside words that already
/// hold a digit, so labels such as TOTAL, OFF or km stay as they are.
String normalizeDigits(String text) => text.split(' ').map((word) {
      if (!word.contains(RegExp(r'\d'))) return word;
      return word.split('').map((c) => _lookalikeDigits[c] ?? c).join();
    }).join(' ');

/// Picks the reading nearest a TOTAL / ODO / TRIP label. Lines with a colon
/// (the clock) and single digits (the gear) are skipped. Without a label it
/// falls back to the tallest number, which is usually the main reading.
///
/// With [lastOdometer] known, readings that make sense win over closer ones:
/// a TOTAL between the last reading and 5,000 km past it, or a TRIP of at
/// most 5,000 km. Speedometer dial numbers rarely pass that test.
OdometerRead parseOdometer(List<ScanLine> lines, {int? lastOdometer}) {
  ScanLine? labelLine;
  String? label;
  for (final l in lines) {
    final m = _labelPattern.firstMatch(l.text);
    if (m != null) {
      labelLine = l;
      label = m.group(1)!.toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
      break;
    }
  }

  final found = <(int, ScanLine)>[];
  for (final l in lines) {
    if (l.text.contains(':')) continue;
    final digitsOnly =
        normalizeDigits(l.text).replaceAll(RegExp(r'[\s,.]'), '');
    for (final m in RegExp(r'\d{2,7}').allMatches(digitsOnly)) {
      found.add((int.parse(m.group(0)!), l));
    }
  }
  if (found.isEmpty) return OdometerRead(label: label);

  if (labelLine != null) {
    final c = labelLine.box.center;
    found.sort((a, b) => (a.$2.box.center - c)
        .distance
        .compareTo((b.$2.box.center - c).distance));
  } else {
    found.sort((a, b) => b.$2.box.height.compareTo(a.$2.box.height));
  }
  final isTrip = label?.startsWith('TRIP') ?? false;
  bool plausible(int v) => isTrip
      ? v <= 5000
      : lastOdometer == null || (v >= lastOdometer && v <= lastOdometer + 5000);
  // Keeps the distance order inside each group.
  final good = found.where((f) => plausible(f.$1)).toList();
  final ordered = [...good, ...found.where((f) => !plausible(f.$1))];
  // When a range applies and nothing fits it, fill nothing rather than a
  // dial number or a reading that lost a digit.
  final checked = isTrip || lastOdometer != null;
  return OdometerRead(
    value: checked && good.isEmpty ? null : ordered.first.$1,
    label: label,
    candidates: ordered.map((f) => f.$1).toList(),
  );
}

/// Finds amount, litres and rate that agree: litres × rate ≈ amount.
/// A number whose decimal point was missed (85554) is also tried as /100.
PumpRead parsePump(List<ScanLine> lines) {
  final nums = <double>{};
  for (final l in lines) {
    final t = normalizeDigits(l.text).replaceAll(',', '.').replaceAll(' ', '');
    for (final m in RegExp(r'\d+(\.\d+)?').allMatches(t)) {
      final s = m.group(0)!;
      final v = double.parse(s);
      if (v <= 0) continue;
      nums.add(v);
      if (!s.contains('.') && s.length >= 3) nums.add(v / 100);
    }
  }
  final list = nums.toList();
  (double, double, double)? best;
  var bestErr = double.infinity;
  for (final a in list) {
    for (final l in list) {
      for (final r in list) {
        if (a == l || a == r || l == r) continue;
        if (r < 60 || r > 160) continue; // plausible petrol rate, ₹/L
        if (l > 80) continue; // plausible litres for one fill
        final err = (l * r - a).abs();
        if (err <= max(1.0, a * 0.005) && err < bestErr) {
          bestErr = err;
          best = (a, l, r);
        }
      }
    }
  }
  if (best == null) return PumpRead(numbers: list);
  return PumpRead(
    amount: best.$1,
    litres: best.$2,
    rate: best.$3,
    error: bestErr,
    numbers: list,
  );
}

/// One scan: the photo, the raw text and what the parser made of it.
class ScanResult {
  final ScanKind kind;
  final String photoPath;
  final List<ScanLine> lines;
  final int elapsedMs;
  final OdometerRead? odometer;
  final PumpRead? pump;

  /// The reading the odometer was checked against, null when unknown.
  final int? lastOdometer;
  final DateTime at;

  ScanResult({
    required this.kind,
    required this.photoPath,
    required this.lines,
    required this.elapsedMs,
    this.odometer,
    this.pump,
    this.lastOdometer,
  }) : at = DateTime.now();

  /// One-line outcome for the form.
  String get summary {
    if (kind == ScanKind.odometer) {
      final o = odometer!;
      if (o.value == null) {
        if (o.candidates.isEmpty) return 'Odometer: no number found';
        return lastOdometer == null
            ? 'Odometer: no trip reading under 5,000 km'
            : 'Odometer: no reading within 5,000 km of $lastOdometer km';
      }
      final how = o.label == null ? 'no label, check it' : o.label!;
      return 'Odometer: ${o.value} km ($how)';
    }
    final p = pump!;
    if (!p.found) return "Pump: numbers didn't agree";
    return 'Pump: ₹${p.amount} · ${p.litres} L · ₹${p.rate}/L';
  }

  /// Plain-text bug report: device, outcome and every recognised line with
  /// its position, so a misread can be traced without the phone attached.
  String report(String appVersion) {
    final b = StringBuffer()
      ..writeln('FuelPulse scan report')
      ..writeln('App: $appVersion')
      ..writeln('Device: ${Platform.operatingSystem} '
          '${Platform.operatingSystemVersion}')
      ..writeln('Time: ${at.toIso8601String()}')
      ..writeln('Photo: ${kind.name}, recognised in $elapsedMs ms')
      ..writeln('Result: $summary');
    if (odometer != null) {
      b.writeln('Odometer label: ${odometer!.label ?? 'none'}; '
          'candidates: ${odometer!.candidates}; '
          'last odometer: ${lastOdometer ?? 'none'}');
    }
    if (pump != null) {
      b.writeln('Pump numbers seen: ${pump!.numbers}'
          '${pump!.error == null ? '' : '; error ₹${pump!.error!.toStringAsFixed(2)}'}');
    }
    b.writeln('Recognised lines (${lines.length}):');
    for (final l in lines) {
      final r = l.box;
      b.writeln('  "${l.text}" at ${r.left.round()},${r.top.round()} '
          'size ${r.width.round()}x${r.height.round()}');
    }
    return b.toString();
  }

  /// Opens the share sheet with the report text and the photo attached.
  Future<void> share(String appVersion) => SharePlus.instance.share(ShareParams(
        subject: 'FuelPulse scan report (${kind.name})',
        text: report(appVersion),
        files: [XFile(photoPath)],
      ));
}

/// Runs ML Kit on a photo. Close it when the form goes away.
class PhotoScanner {
  final _recognizer = TextRecognizer(script: TextRecognitionScript.latin);

  Future<ScanResult> scan(String path, ScanKind kind,
      {int? lastOdometer}) async {
    final sw = Stopwatch()..start();
    final text = await _recognizer.processImage(InputImage.fromFilePath(path));
    sw.stop();
    final lines = [
      for (final block in text.blocks)
        for (final line in block.lines) ScanLine(line.text, line.boundingBox),
    ];
    return ScanResult(
      kind: kind,
      photoPath: path,
      lines: lines,
      elapsedMs: sw.elapsedMilliseconds,
      odometer: kind == ScanKind.odometer
          ? parseOdometer(lines, lastOdometer: lastOdometer)
          : null,
      pump: kind == ScanKind.pump ? parsePump(lines) : null,
      lastOdometer: lastOdometer,
    );
  }

  Future<void> close() => _recognizer.close();
}
