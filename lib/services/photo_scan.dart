import 'dart:io';
import 'dart:math';
import 'dart:ui' show Rect;

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'app_lock.dart';

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

/// What the pump photo gave. Amount and litres are null unless all three
/// agree: litres × rate must come within about ₹1 of the amount. When they
/// can't be checked, [rate] alone may still be set, because a pump rate is
/// the one number narrow enough ([kMinRate] to [kMaxRate]) to trust unchecked.
class PumpRead {
  final double? amount;
  final double? litres;
  final double? rate;
  final double? error;
  final List<double> numbers;

  /// Digits changed to make litres × rate match the amount; 0 when all three
  /// were read as they are.
  final int corrections;

  const PumpRead({
    this.amount,
    this.litres,
    this.rate,
    this.error,
    this.numbers = const [],
    this.corrections = 0,
  });

  bool get found => amount != null;

  /// Only the rate could be read; litres and amount were missing or didn't
  /// agree with it.
  bool get rateOnly => amount == null && rate != null;
}

/// Plausible pump rates in ₹ a litre. Premium petrol (XP100, Speed 100,
/// Power 100) reached ₹167 in 2026; pump density readings (700 to 800
/// kg/m³) stay above the top, so they can't pass as a rate.
const kMinRate = 60.0;
const kMaxRate = 200.0;

/// A fill to offer when the pump numbers didn't agree: the rate (read, or
/// the only number in the rate range), the largest other number as the
/// amount, and litres = amount ÷ rate. Null when the read agreed, or no
/// rate or amount stands out. All three come back so the form can set them
/// together without the total drifting from the rounded litres.
({double litres, double rate, double amount})? pumpSuggestion(PumpRead r) {
  if (r.found) return null;
  var rate = r.rate;
  if (rate == null) {
    final inRange =
        r.numbers.where((n) => n >= kMinRate && n <= kMaxRate).toSet();
    if (inRange.length != 1) return null;
    rate = inRange.first;
  }
  final bigger = r.numbers.where((n) => n > rate! + 0.001);
  if (bigger.isEmpty) return null;
  final amount = bigger.reduce(max);
  final litres = double.parse((amount / rate).toStringAsFixed(2));
  return (litres: litres, rate: rate, amount: amount);
}

/// Litres from [pumpSuggestion], or null.
double? suggestLitres(PumpRead r) => pumpSuggestion(r)?.litres;

/// Digits a seven-segment display is commonly misread as, from real scans:
/// 127.43 read as 121.43 (7 as 1). A thin 1 can also vanish entirely
/// (11.38 read as 138), which [_digitVariants] covers by inserting a 1.
const _segmentMixups = {
  '1': ['7', '4'],
  '7': ['1'],
  '4': ['1'],
  '5': ['6', '9'],
  '6': ['5', '8'],
  '8': ['0', '6', '9', '3'],
  '0': ['8'],
  '9': ['8', '5'],
  '3': ['8'],
};

/// The digit string as read, with one segment slip swapped, or with one
/// missing 1 put back. Maps each variant to its number of changes (0 or 1).
Map<String, int> _digitVariants(String digits) {
  final out = <String, int>{digits: 0};
  for (var i = 0; i < digits.length; i++) {
    for (final r in _segmentMixups[digits[i]] ?? const <String>[]) {
      out.putIfAbsent(digits.replaceRange(i, i + 1, r), () => 1);
    }
  }
  for (var i = 0; i <= digits.length; i++) {
    out.putIfAbsent(digits.replaceRange(i, i, '1'), () => 1);
  }
  return out;
}

/// When the amount was read but litres and rate don't agree with it, tries
/// one segment slip in litres and one in the rate (two-decimal display
/// values). A pump shows amount = litres × rate rounded to the paisa, so a
/// pair is accepted only within ₹0.011, far tighter than the plain check.
/// Fewest changes win, then the smallest error.
PumpRead? _repairFromAmount(List<String> tokens, List<double> amounts) {
  final litres = <(double, int, int)>[]; // value, changes, token
  final rates = <(double, int, int)>[];
  for (var t = 0; t < tokens.length; t++) {
    _digitVariants(tokens[t]).forEach((v, changes) {
      final x = int.parse(v) / 100;
      if (x >= 0.5 && x <= 80) litres.add((x, changes, t));
      if (x >= kMinRate && x <= kMaxRate) rates.add((x, changes, t));
    });
  }
  (double, double, double, int, double)? best;
  for (final a in amounts.where((a) => a >= 10)) {
    for (final l in litres) {
      for (final r in rates) {
        if (l.$3 == r.$3) continue; // one display, one value
        final changes = l.$2 + r.$2;
        if (changes == 0) continue; // the plain check already looked
        final err = (l.$1 * r.$1 - a).abs();
        if (err > 0.011) continue;
        if (best == null ||
            changes < best.$4 ||
            (changes == best.$4 && err < best.$5)) {
          best = (a, l.$1, r.$1, changes, err);
        }
      }
    }
  }
  if (best == null) return null;
  return PumpRead(
    amount: best.$1,
    litres: best.$2,
    rate: best.$3,
    error: best.$5,
    corrections: best.$4,
  );
}

final _rateLabel = RegExp(r'rate|rs\s*/\s*l|₹\s*/\s*l|price|/\s*lit',
    caseSensitive: false);

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
/// Without an agreeing set it falls back to the rate alone, see [PumpRead].
PumpRead parsePump(List<ScanLine> lines) {
  final nums = <double>{};
  final where = <double, ScanLine>{};
  final tokens = <String>{}; // digit runs without their point, for repairs
  for (final l in lines) {
    // ML Kit splits one display into words ("1450. 15") and merges two
    // displays into one line ("164 16 135" is density 764.1 and rate 167.35),
    // so every run of up to three neighbouring words is a candidate.
    final words = normalizeDigits(l.text)
        .split(RegExp(r'\s+'))
        .map((w) => w.replaceAll(RegExp(r'[^\d]'), ''))
        .toList();
    for (var i = 0; i < words.length; i++) {
      for (var j = i; j < words.length && j < i + 3; j++) {
        final digits = words.sublist(i, j + 1).join();
        if (digits.length >= 2) tokens.add(digits);
      }
    }
    final t = normalizeDigits(l.text).replaceAll(',', '.').replaceAll(' ', '');
    for (final m in RegExp(r'\d+(\.\d+)?').allMatches(t)) {
      final s = m.group(0)!;
      final v = double.parse(s);
      if (v <= 0) continue;
      nums.add(v);
      where.putIfAbsent(v, () => l);
      if (!s.contains('.') && s.length >= 3) {
        nums.add(v / 100);
        where.putIfAbsent(v / 100, () => l);
      }
    }
  }
  final list = nums.toList();
  (double, double, double)? best;
  var bestErr = double.infinity;
  for (final a in list) {
    for (final l in list) {
      for (final r in list) {
        if (a == l || a == r || l == r) continue;
        if (r < kMinRate || r > kMaxRate) continue;
        if (l > 80) continue; // plausible litres for one fill
        final err = (l * r - a).abs();
        if (err <= max(1.0, a * 0.005) && err < bestErr) {
          bestErr = err;
          best = (a, l, r);
        }
      }
    }
  }
  if (best == null) {
    final repaired = _repairFromAmount(tokens.toList(), list);
    if (repaired != null) {
      return PumpRead(
        amount: repaired.amount,
        litres: repaired.litres,
        rate: repaired.rate,
        error: repaired.error,
        corrections: repaired.corrections,
        numbers: list,
      );
    }
    return PumpRead(rate: _rateAlone(list, where, lines), numbers: list);
  }
  return PumpRead(
    amount: best.$1,
    litres: best.$2,
    rate: best.$3,
    error: bestErr,
    numbers: list,
  );
}

/// The single number in the rate range. With several, the one nearest
/// a rate label (Rate, Rs/Lit, ₹/L, Price) wins; with several and no label,
/// none is trusted.
double? _rateAlone(
    List<double> nums, Map<double, ScanLine> where, List<ScanLine> lines) {
  final rates = nums.where((v) => v >= kMinRate && v <= kMaxRate).toList();
  if (rates.length == 1) return rates.first;
  if (rates.isEmpty) return null;
  final label = lines.where((l) => _rateLabel.hasMatch(l.text)).firstOrNull;
  if (label == null) return null;
  final c = label.box.center;
  rates.sort((a, b) => (where[a]!.box.center - c)
      .distance
      .compareTo((where[b]!.box.center - c).distance));
  return rates.first;
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
    if (p.rateOnly) return 'Pump: only the rate was read, ₹${p.rate}/L';
    if (!p.found) return "Pump: numbers didn't agree";
    if (p.corrections > 0) {
      return 'Pump: ₹${p.amount} · ${p.litres} L · ₹${p.rate}/L '
          '(${p.corrections} ${p.corrections == 1 ? 'digit' : 'digits'} '
          'corrected, check them)';
    }
    return 'Pump: ₹${p.amount} · ${p.litres} L · ₹${p.rate}/L';
  }

  /// Plain-text bug report: device, outcome and every recognised line with
  /// its position, so a misread can be traced without the phone attached.
  String report(String appVersion) {
    final b = StringBuffer()
      ..writeln("My H'ness scan report")
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
      b.writeln('Pump numbers seen: ${pump!.numbers}; '
          'digits corrected: ${pump!.corrections}'
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
        subject: "My H'ness scan report (${kind.name})",
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

/// Reads the odometer from a photo, taken with the camera or picked from
/// the gallery. Null when cancelled or unread.
Future<int?> scanOdometer(int? last,
    {ImageSource source = ImageSource.camera}) async {
  final x = await withoutRelock(() => ImagePicker()
      .pickImage(source: source, maxWidth: 2400, imageQuality: 92));
  if (x == null) return null;
  final scanner = PhotoScanner();
  try {
    final r = await scanner.scan(x.path, ScanKind.odometer, lastOdometer: last);
    return r.odometer?.value;
  } finally {
    await scanner.close();
  }
}
