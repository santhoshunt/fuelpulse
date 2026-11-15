import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../theme/app_colors.dart';

final _grouped = NumberFormat('#,##,##0', 'en_IN');

/// One thin bar per week, the month named under the first week of each
/// month. Touch or drag across to lift a week: its dates and km show in a
/// bubble, the rest fade, until the next touch.
class WeekBarChart extends StatefulWidget {
  /// Each week's Monday and its km.
  final List<(DateTime week, double km)> weeks;

  const WeekBarChart({super.key, required this.weeks});

  @override
  State<WeekBarChart> createState() => _WeekBarChartState();
}

class _WeekBarChartState extends State<WeekBarChart> {
  static const _plot = 110.0;
  int? _picked;

  @override
  void didUpdateWidget(WeekBarChart old) {
    super.didUpdateWidget(old);
    if (old.weeks.length != widget.weeks.length) _picked = null;
  }

  void _pick(double dx, double width) {
    final n = widget.weeks.length;
    if (n == 0) return;
    final i = (dx / width * n).floor().clamp(0, n - 1);
    if (i != _picked) setState(() => _picked = i);
  }

  /// "3 to 9 Nov", "29 Sep to 5 Oct".
  static String _dates(DateTime monday) {
    final sunday = DateTime(monday.year, monday.month, monday.day + 6);
    return monday.month == sunday.month
        ? '${monday.day} to ${DateFormat('d MMM').format(sunday)}'
        : '${DateFormat('d MMM').format(monday)} to '
            '${DateFormat('d MMM').format(sunday)}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final weeks = widget.weeks;
    final n = weeks.length;
    final top = n == 0 ? 0.0 : weeks.map((w) => w.$2).reduce(math.max);
    final label = TextStyle(color: colors.textSecondary, fontSize: 11);
    // Months whose first week is in the chart, at most six named.
    final starts = [
      for (var i = 0; i < n; i++)
        if (i == 0 || weeks[i].$1.month != weeks[i - 1].$1.month) i,
    ];
    final every = math.max(1, (starts.length / 6).ceil());
    final named = [for (var j = 0; j < starts.length; j += every) starts[j]];
    final yearly = n > 0 && weeks.first.$1.year != weeks.last.$1.year;
    return TapRegion(
      onTapOutside: (_) {
        if (_picked != null) setState(() => _picked = null);
      },
      child: LayoutBuilder(
        builder: (context, box) {
          final slot = box.maxWidth / math.max(1, n);
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (d) => _pick(d.localPosition.dx, box.maxWidth),
            onHorizontalDragStart: (d) => _pick(d.localPosition.dx, box.maxWidth),
            onHorizontalDragUpdate: (d) =>
                _pick(d.localPosition.dx, box.maxWidth),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: _plot + 34,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Bars stand on the bottom edge; the room above the
                      // tallest one is for the bubble.
                      Positioned.fill(
                       child: Container(
                        decoration: BoxDecoration(
                            border: Border(
                                bottom: BorderSide(color: colors.cardBorder))),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            for (var i = 0; i < n; i++)
                              Expanded(
                                child: AnimatedOpacity(
                                  duration: const Duration(milliseconds: 180),
                                  opacity:
                                      _picked == null || _picked == i ? 1 : 0.35,
                                  child: Container(
                                    constraints:
                                        const BoxConstraints(maxWidth: 22),
                                    margin: EdgeInsets.symmetric(
                                        horizontal: slot > 6 ? 1.5 : 0.5),
                                    // An empty week keeps a sliver.
                                    height: top > 0
                                        ? math.max(2, _plot * weeks[i].$2 / top)
                                        : 2,
                                    decoration: BoxDecoration(
                                      color: colors.secondary,
                                      borderRadius: const BorderRadius.vertical(
                                          top: Radius.circular(3)),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                       ),
                      ),
                      if (_picked case final p? when p < n)
                        Positioned(
                          top: 0,
                          left: ((p + 0.5) * slot - 90)
                              .clamp(0.0, math.max(0.0, box.maxWidth - 180)),
                          width: 180,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: colors.textPrimary,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                  '${_dates(weeks[p].$1)} · '
                                  '${_grouped.format(weeks[p].$2.round())} km',
                                  style: TextStyle(
                                      color: colors.card,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                SizedBox(
                  height: 16,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      for (final i in named)
                        Positioned(
                          // Kept inside the chart at both ends.
                          left: (i * slot).clamp(0.0, math.max(0.0, box.maxWidth - 44)),
                          child: Text(
                              DateFormat(yearly ? "MMM ''yy" : 'MMM')
                                  .format(weeks[i].$1),
                              style: label),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
