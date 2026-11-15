import 'package:flutter_test/flutter_test.dart';

import 'package:fuelpulse/utils/weekly_distance.dart';

void main() {
  test('weeks start on Monday', () {
    // 5 Nov 2026 is a Thursday.
    expect(weekStart(DateTime(2026, 11, 5, 18)), DateTime(2026, 11, 2));
    expect(weekStart(DateTime(2026, 11, 2)), DateTime(2026, 11, 2));
    expect(weekStart(DateTime(2026, 11, 8, 23)), DateTime(2026, 11, 2));
  });

  test('km between two readings spreads over the weeks between them', () {
    final weeks = weeklyDistance([
      (DateTime(2026, 11, 2), 1000),
      (DateTime(2026, 11, 16), 1140),
    ], DateTime(2026, 11, 2), DateTime(2026, 11, 22));
    expect(weeks.map((w) => w.$1),
        [DateTime(2026, 11, 2), DateTime(2026, 11, 9), DateTime(2026, 11, 16)]);
    expect(weeks.map((w) => w.$2.round()), [70, 70, 0]);
  });

  test('a reading below an earlier one is skipped', () {
    final weeks = weeklyDistance([
      (DateTime(2026, 11, 2), 1000),
      (DateTime(2026, 11, 4), 100), // a typo
      (DateTime(2026, 11, 9), 1210),
    ], DateTime(2026, 11, 2), DateTime(2026, 11, 8));
    expect(weeks.single.$2.round(), 210);
  });

  test('only the part inside the period counts', () {
    final weeks = weeklyDistance([
      (DateTime(2026, 10, 26), 0),
      (DateTime(2026, 11, 9), 280),
    ], DateTime(2026, 11, 2), DateTime(2026, 11, 8));
    expect(weeks.single.$2.round(), 140);
  });
}
