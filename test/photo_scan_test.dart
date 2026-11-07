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

    test('a 7 read as 1 in the litres is repaired from the amount', () {
      final r = parsePump([
        line('855.54', 0, 0, 10, 10),
        line('1.94', 0, 20, 10, 10),
        line('107.75', 0, 40, 10, 10),
      ]);
      expect(r.found, isTrue);
      expect(r.litres, 7.94);
      expect(r.corrections, 1);
    });

    test('without an amount a broken sum keeps only the rate', () {
      final r = parsePump([
        line('1.94', 0, 20, 10, 10),
        line('107.75', 0, 40, 10, 10),
      ]);
      expect(r.found, isFalse);
      expect(r.rate, 107.75);
    });

    // 6 lines from pump 15 showing ₹830.06, 4.96 L, density 764.1 and
    // ₹167.35/L (v2.1.3 report): decimals lost, and the density and rate
    // windows merged into one line with the rate's 7 read as 1.
    test('real photo: merged density and rate line still yields 167.35', () {
      final r = parsePump([
        line('15', 546, 472, 128, 122),
        line('Amount ()', 493, 614, 155, 42),
        line('83006', 492, 652, 224, 88),
        line('496', 576, 750, 147, 89),
        line('Volume (L)', 485, 826, 142, 43),
        line('164 16 135', 421, 875, 301, 70),
      ]);
      expect(r.found, isTrue);
      expect(r.amount, 830.06);
      expect(r.litres, 4.96);
      expect(r.rate, 167.35);
      expect(r.corrections, 1);
    });

    // The 4 lines ML Kit returned for a real pump photo (₹1188.24, 10.47 L,
    // ₹113.49/L) in a v2.1.3 scan report. Amount and litres were not read.
    test('real photo: only the rate survives, decimal point restored', () {
      final r = parsePump([
        line('aA Rupees', 1157, 1538, 1172, 172),
        line('11349', 1206, 2187, 459, 144),
        line('Litre', 1985, 1902, 256, 99),
        line('Rs/Lit', 2022, 2246, 285, 114),
      ]);
      expect(r.found, isFalse);
      expect(r.rateOnly, isTrue);
      expect(r.rate, 113.49);
    });

    test('premium fuel at ₹167.35/L next to a density reading', () {
      // Sample photo layout: amount, litres, density 762.3, rate 167.35.
      final r = parsePump([
        line('Amount (₹)', 0, 0, 100, 20),
        line('1564.72', 0, 30, 200, 60),
        line('9.35', 100, 100, 100, 60),
        line('Volume (L)', 0, 170, 100, 20),
        line('762.3', 0, 200, 80, 30),
        line('167.35', 120, 200, 80, 30),
        line('Density (Kg/m³)', 0, 235, 80, 15),
        line('Rate (₹/L)', 120, 235, 80, 15),
      ]);
      expect(r.found, isTrue);
      expect(r.rate, 167.35);
      expect(r.litres, 9.35);
      expect(r.amount, 1564.72);
    });

    // 17 lines ML Kit returned for a Tokheim pump showing ₹1450.15, 11.38 L
    // and ₹127.43/L (v2.1.3 report): litres lost a 1 ("H138") and the rate
    // read its 7 as a 1 ("12143").
    final tokheimYellow = [
      line('ets', 2, 476, 54, 44),
      line('2VIR)', 3, 545, 37, 11),
      line('66-C', -1, 563, 34, 19),
      line('WAY', 55, 581, 43, 28),
      line('PA, No, 6,095.221', 0, 602, 69, 16),
      line('A', 34, 658, 3, 7),
      line('Amount', 247, 663, 96, 18),
      line('Volume', 247, 820, 91, 20),
      line('TOKHEIN', 241, 878, 86, 27),
      line('1450. 15', 348, 549, 391, 116),
      line('H138', 419, 710, 322, 127),
      line('L', 723, 837, 11, 17),
      line('12143', 429, 880, 305, 122),
      line('Rate', 396, 993, 48, 16),
      line('/L', 692, 1008, 39, 19),
      line('CLE', 1059, 943, 19, 9),
      line('ENI', 1053, 982, 22, 15),
    ];

    test('real photo: two segment slips repaired from the amount', () {
      final r = parsePump(tokheimYellow);
      expect(r.found, isTrue);
      expect(r.amount, 1450.15);
      expect(r.litres, 11.38);
      expect(r.rate, 127.43);
      expect(r.corrections, 2);
    });

    // 10 lines from a Tokheim pump showing ₹938.01 and 8.67 L in a bright
    // window and ₹108.19/L (v2.1.3 report): only the rate was read.
    test('real photo: bright amount window unread, rate alone kept', () {
      final r = parsePump([
        line('Density', 325, 390, 64, 29),
        line('Rate', 349, 705, 38, 22),
        line('Kg/m', 432, 380, 45, 24),
        line('Amount ()', 721, 229, 177, 57),
        line('Volume (L)', 749, 513, 177, 54),
        line('108.19', 655, 580, 171, 91),
        line('TOKHEIN', 656, 706, 57, 24),
        line('Rate (/L)', 673, 668, 102, 29),
        line('Rate (/L)', 907, 639, 109, 32),
        line('ENSURE REGISTER SET TO ZERO BEFORE DELIVERY', 564, 809, 518, 71),
      ]);
      expect(r.rateOnly, isTrue);
      expect(r.rate, 108.19);
    });

    // 26 lines ML Kit returned for a Gilbarco pump showing ₹768.41, 7.59 L,
    // density 754.2 and ₹101.24/L (v2.1.3 report): every display misread.
    test('real photo: garbled segment digits fill nothing', () {
      final r = parsePump([
        line('ENSURE ZERO BEFORE DELIVER', 279, 413, 530, 53),
        line('7584', 471, 492, 262, 128),
        line('159', 599, 621, 208, 151),
        line('Density Kgim', 307, 1022, 185, 38),
        line('Ltre', 409, 1227, 63, 42),
        line('Litre', 495, 791, 106, 39),
        line('POWEROI', 661, 903, 134, 21),
        line('NOZZLE B1 Cu.U1', 998, 832, 165, 24),
        line('277551.550', 1067, 850, 113, 23),
        line('2 3', 1054, 909, 79, 28),
        line('Sale', 1169, 924, 27, 14),
        line('Litre', 1169, 980, 28, 12),
      ]);
      expect(r.found, isFalse);
      expect(r.rate, isNull);
    });

    test('two rate-sized numbers and no rate label trust neither', () {
      final r = parsePump([
        line('120.00', 0, 0, 10, 10),
        line('104.20', 0, 20, 10, 10),
      ]);
      expect(r.rate, isNull);
    });

    test('two rate-sized numbers: the one next to Rs/Lit wins', () {
      final r = parsePump([
        line('120.00', 0, 0, 100, 40),
        line('104.20', 0, 300, 100, 40),
        line('Rs/Lit', 150, 300, 80, 40),
      ]);
      expect(r.rate, 104.20);
    });
  });
}
