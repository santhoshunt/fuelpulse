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
