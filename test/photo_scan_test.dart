import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:fuelpulse/services/photo_scan.dart';

ScanLine line(String t, double x, double y, double w, double h) =>
    ScanLine(t, Rect.fromLTWH(x, y, w, h));

void main() {
  group('parseOdometer', () {
    // Shaped like the bike LCD: TOTAL label, reading, gear and clock.
    final totalLcd = [
      line('TOTAL', 470, 665, 110, 30),
      line('4477', 520, 740, 200, 70),
      line('km', 425, 815, 50, 25),
      line('N', 415, 900, 100, 120),
      line('7:51', 560, 905, 140, 70),
    ];

    test('reads the number next to TOTAL as the odometer', () {
      final r = parseOdometer(totalLcd);
      expect(r.value, 4477);
      expect(r.label, 'TOTAL');
      expect(r.isTrip, isFalse);
    });

    test('ignores the clock and the gear letter', () {
      expect(parseOdometer(totalLcd).candidates, isNot(contains(751)));
    });

    test('TRIP A means km since the last fill-up', () {
      final r = parseOdometer([
        line('TRIP A', 470, 665, 120, 30),
        line('312', 560, 740, 150, 70),
      ]);
      expect(r.value, 312);
      expect(r.isTrip, isTrue);
    });

    test('without a label it takes the tallest number', () {
      final r = parseOdometer([
        line('12', 10, 10, 30, 20),
        line('45210', 10, 60, 200, 80),
      ]);
      expect(r.value, 45210);
      expect(r.label, isNull);
    });

    test('no digits gives no value', () {
      expect(parseOdometer([line('km', 0, 0, 10, 10)]).value, isNull);
    });

    // The 16 lines ML Kit returned for a real Honda CB350RS odometer photo
    // showing TOTAL 5198, from a v2.1.2 scan report. The 1 came back as "i".
    final realLcd = [
      line('80', 198, 649, 70, 41),
      line('60', 199, 724, 45, 40),
      line('I00', 266, 592, 66, 32),
      line(',40', 169, 812, 85, 38),
      line('20', 221, 893, 60, 32),
      line('20 14O', 350, 554, 159, 31),
      line('km/h', 390, 643, 77, 29),
      line('I60', 516, 586, 69, 36),
      line('TOTAL', 561, 775, 60, 14),
      line('km', 545, 854, 25, 15),
      line('5 i98', 598, 807, 102, 41),
      line('E F', 554, 874, 149, 27),
      line('N', 547, 902, 53, 77),
      line('OFF', 778, 1267, 47, 31),
      line('N.', 966, 775, 61, 35),
      line('((ABS)', 956, 858, 51, 29),
    ];

    test('real photo: "5 i98" next to TOTAL reads as 5198', () {
      expect(parseOdometer(realLcd).value, 5198);
    });

    test('real photo: a lost digit fills nothing when the last reading is known',
        () {
      // Without the letter fix the line gives 98. With the last reading at
      // 4,800 km nothing on the display fits, so nothing may be filled.
      final misread = [
        for (final l in realLcd)
          l.text == '5 i98' ? line('5 #98', 598, 807, 102, 41) : l,
      ];
      final r = parseOdometer(misread, lastOdometer: 4800);
      expect(r.value, isNull);
      expect(r.candidates, contains(98));
    });

    test('real photo: 5198 fits a last reading of 4,800 km', () {
      expect(parseOdometer(realLcd, lastOdometer: 4800).value, 5198);
    });

    test('a TRIP over 5,000 km is not trusted', () {
      final r = parseOdometer([
        line('TRIP B', 470, 665, 120, 30),
        line('20140', 560, 740, 150, 70),
      ]);
      expect(r.value, isNull);
    });
  });

  group('normalizeDigits', () {
    test('maps look-alike letters inside numbers', () {
      expect(normalizeDigits('I00'), '100');
      expect(normalizeDigits('14O'), '140');
      expect(normalizeDigits('5 i98'), '5 198');
    });

    test('leaves words without digits alone', () {
      expect(normalizeDigits('TOTAL'), 'TOTAL');
      expect(normalizeDigits('OFF'), 'OFF');
      expect(normalizeDigits('N.'), 'N.');
    });
  });

  group('parsePump', () {
    test('finds amount, litres and rate that agree', () {
      final r = parsePump([
        line('Amount (₹)', 500, 750, 250, 40),
        line('855.54', 500, 800, 400, 140),
        line('7.94', 700, 960, 200, 130),
        line('Volume (L)', 490, 1110, 250, 40),
        line('107.75', 650, 1200, 260, 90),
        line('Rate (₹/L)', 690, 1300, 160, 30),
      ]);
      expect(r.found, isTrue);
      expect(r.amount, 855.54);
      expect(r.litres, 7.94);
      expect(r.rate, 107.75);
    });

    test('recovers a missed decimal point', () {
      final r = parsePump([
        line('85554', 0, 0, 10, 10),
        line('7.94', 0, 20, 10, 10),
        line('107.75', 0, 40, 10, 10),
      ]);
      expect(r.amount, 855.54);
    });

    test('a misread digit that breaks the sum fills nothing', () {
      final r = parsePump([
        line('855.54', 0, 0, 10, 10),
        line('1.94', 0, 20, 10, 10),
        line('107.75', 0, 40, 10, 10),
      ]);
      expect(r.found, isFalse);
    });
  });
}
