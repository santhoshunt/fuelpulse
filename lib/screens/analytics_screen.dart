import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../db/database_helper.dart';
import '../models/fuel_log.dart';
import '../models/pump.dart';
import '../models/service_record.dart';
import '../models/service_type.dart';
import '../models/vehicle.dart';
import '../theme/app_colors.dart';
import '../utils/cost_calculator.dart';
import '../utils/efficiency_calculator.dart';
import '../utils/page_routes.dart';
import '../utils/period_filter.dart';
import '../utils/service_schedule.dart';
import '../utils/trend_calculator.dart';
import '../utils/vehicle_manager.dart';
import '../widgets/brand_logo.dart';
import '../widgets/month_bar_chart.dart';
import '../widgets/month_line_chart.dart';
import '../widgets/period_selector.dart';
import '../widgets/trend_chart.dart';
import 'service_screen.dart' show dueText, latestOdometer, serviceTypeNames;
import 'year_report_screen.dart';

final _grouped = NumberFormat('#,##,##0', 'en_IN');

/// The Analytics tab for the active vehicle: monthly fuel spend, mileage
/// over time, the price paid, brand and fuel grade comparisons, and totals.
/// One period, picked at the top, applies to every card. Vehicles are never mixed: one vehicle's km/L
/// next to another's would average into a meaningless number.
class AnalyticsScreen extends StatefulWidget {
  final ValueNotifier<int> reload;

  /// Fixes "now" for the period windows in tests.
  @visibleForTesting
  final DateTime? now;

  const AnalyticsScreen({super.key, required this.reload, this.now});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final _db = DatabaseHelper();
  Vehicle? _vehicle;
  List<FuelLog> _chrono = const [];
  bool _loading = true;
  AnalyticsPeriod _period = const AnalyticsPeriod(PeriodKind.last12);
  bool _pumpByCost = false;
  bool _gradeByCost = false;
  bool _serviceView = false;
  Map<String, Pump> _pumps = const {};
  List<ServiceRecord> _services = const [];
  Map<String, ServiceType> _types = const {};
  int? _odometer;

  DateTime get _now => widget.now ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    widget.reload.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(AnalyticsScreen old) {
    super.didUpdateWidget(old);
    if (old.reload != widget.reload) {
      old.reload.removeListener(_load);
      widget.reload.addListener(_load);
    }
  }

  @override
  void dispose() {
    widget.reload.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final vehicle = await loadActiveVehicle();
    final chrono = await _db.getAllLogsChrono(vehicle.id);
    final pumps = await _db.getPumps();
    final services = await _db.getServices(vehicle.id);
    final types = await _db.getServiceTypes();
    final odo = await latestOdometer(vehicle.id);
    if (!mounted) return;
    setState(() {
      _vehicle = vehicle;
      _chrono = chrono;
      _pumps = {for (final p in pumps) p.id: p};
      _services = services;
      _types = {for (final t in types) t.id: t};
      _odometer = odo;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Analytics',
                            style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.5)),
                      ),
                      IconButton(
                        tooltip: 'Year report',
                        icon: Icon(Icons.ios_share, color: colors.primary),
                        onPressed: () => Navigator.push(
                            context,
                            SmoothPageRoute(
                                page: YearReportScreen(now: widget.now))),
                      ),
                      ActionChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_periodLabel),
                            const Icon(Icons.expand_more, size: 18),
                          ],
                        ),
                        onPressed: _pickPeriod,
                      ),
                    ],
                  ),
                  Text(_vehicle?.name ?? '',
                      style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 15,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 14),
                  PeriodSelector(
                    months: _serviceView ? 1 : 0,
                    options: const [0, 1],
                    label: (v) => v == 0 ? 'Fuel' : 'Service',
                    onChanged: (v) => setState(() => _serviceView = v == 1),
                  ),
                  const SizedBox(height: 14),
                  if (_serviceView)
                    ..._serviceCards(colors)
                  else if (_chrono.isEmpty)
                    _notEnough(colors)
                  else ...[
                    _spendCard(colors),
                    const SizedBox(height: 14),
                    _mileageCard(),
                    ..._priceCard(colors),
                    ..._pumpCard(colors),
                    ..._gradeCard(colors),
                    const SizedBox(height: 14),
                    _totalsCard(colors),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _notEnough(AppColors colors) {
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Column(
        children: [
          Icon(Icons.bar_chart_outlined,
              size: 64, color: colors.textSecondary.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text('Not enough data',
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          Text('Add fill-ups to see spend, mileage and comparisons.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _card(List<Widget> children) => Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      );

  Widget _head(String caption, String? value, AppColors colors) => Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Expanded(child: _cap(caption, colors)),
          if (value != null)
            Text(value,
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 20,
                    fontWeight: FontWeight.w700)),
        ],
      );

  Widget _cap(String s, AppColors colors) => Text(s.toUpperCase(),
      style: TextStyle(
          color: colors.textSecondary,
          fontSize: 11,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600));

  // ── Period ──────────────────────────────────────────────────────────

  ({DateTime from, DateTime to}) get _range =>
      periodRange(_period, _chrono, now: _now);

  bool _inRange(String timestamp) {
    final at = DateTime.tryParse(timestamp);
    final r = _range;
    return at != null && !at.isBefore(r.from) && !at.isAfter(r.to);
  }

  String get _periodLabel => switch (_period.kind) {
        PeriodKind.last12 => '12 months',
        PeriodKind.overall => 'Overall',
        PeriodKind.custom => '${DateFormat('d MMM yy').format(_range.from)} '
            'to ${DateFormat('d MMM yy').format(_range.to)}',
      };

  /// [items] summed per month across the period, every month present.
  List<(DateTime, double)> _monthly(Iterable<(String, double)> items) {
    final r = _range;
    final months = monthsBetween(r.from, r.to);
    final sums = List<double>.filled(months.length, 0);
    for (final (ts, v) in items) {
      final at = DateTime.tryParse(ts);
      if (at == null || at.isBefore(r.from) || at.isAfter(r.to)) continue;
      final i = (at.year - r.from.year) * 12 + at.month - r.from.month;
      if (i >= 0 && i < sums.length) sums[i] += v;
    }
    return [for (var i = 0; i < months.length; i++) (months[i], sums[i])];
  }

  /// A bar a month up to 12 months; a line you drag along beyond that.
  Widget _monthChart(List<(DateTime, double)> points) {
    String money(double v) => '₹${_grouped.format(v)}';
    return points.length <= 12
        ? MonthBarChart(bars: points, formatValue: money)
        : MonthLineChart(points: points, formatValue: money);
  }

  Future<void> _pickPeriod() async {
    final colors = AppColors.of(context);
    final picked = await showModalBottomSheet<PeriodKind>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (k, label) in const [
              (PeriodKind.last12, 'Last 12 months'),
              (PeriodKind.overall, 'Overall'),
              (PeriodKind.custom, 'Custom range…'),
            ])
              ListTile(
                leading: k == PeriodKind.custom
                    ? Icon(Icons.date_range, color: colors.primary)
                    : null,
                title: Text(label),
                trailing: _period.kind == k
                    ? Icon(Icons.check, color: colors.primary)
                    : null,
                onTap: () => Navigator.pop(ctx, k),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    if (picked != PeriodKind.custom) {
      setState(() => _period = AnalyticsPeriod(picked));
      return;
    }
    final custom = await showModalBottomSheet<AnalyticsPeriod>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CustomRangeSheet(now: _now, current: _period),
    );
    if (custom != null && mounted) setState(() => _period = custom);
  }

  Widget _spendCard(AppColors colors) {
    final bars = _monthly([
      for (final log in _chrono)
        if ((log.totalCost ?? computeTotalCost(log.pricePerLitre, log.liters))
            case final spend?)
          (log.timestamp, spend),
    ]);
    final total = bars.fold<double>(0, (s, b) => s + b.$2);
    return _card([
      _head('Fuel expenses', '₹${_grouped.format(total)}', colors),
      const SizedBox(height: 12),
      _monthChart(bars),
    ]);
  }

  Widget _mileageCard() {
    final r = _range;
    final trend = calculateSegmentTrend(_chrono)
        .where((p) => !p.closedAt.isBefore(r.from) && !p.closedAt.isAfter(r.to))
        .toList();
    return TrendChart(
      title: 'Fuel mileage (km/L)',
      points: trend.map((p) => TrendPoint(p.closedAt, p.kmPerLitre)).toList(),
      formatValue: (v) => v.toStringAsFixed(1),
      emptyMessage: 'Trend appears after 2 completed full-tank segments.',
    );
  }

  /// What each fill-up in the period cost a litre, and how the average
  /// compares with the same months a year earlier.
  List<Widget> _priceCard(AppColors colors) {
    double? priceOf(FuelLog l) =>
        l.pricePerLitre ?? computePricePerLitre(l.totalCost, l.liters);
    final points = [
      for (final l in _chrono)
        if (_inRange(l.timestamp) && priceOf(l) != null)
          TrendPoint(DateTime.parse(l.timestamp), priceOf(l)!),
    ];
    if (points.isEmpty) return const [];
    double? average(DateTime from, DateTime to) {
      var spend = 0.0, litres = 0.0;
      for (final l in _chrono) {
        final at = DateTime.tryParse(l.timestamp);
        final p = priceOf(l);
        if (at == null || p == null || at.isBefore(from) || at.isAfter(to)) {
          continue;
        }
        spend += p * l.liters;
        litres += l.liters;
      }
      return litres > 0 ? spend / litres : null;
    }

    final r = _range;
    final now = average(r.from, r.to);
    final before = average(DateTime(r.from.year - 1, r.from.month, r.from.day),
        DateTime(r.to.year - 1, r.to.month, r.to.day, 23, 59, 59));
    final diff = now != null && before != null ? now - before : null;
    return [
      const SizedBox(height: 14),
      TrendChart(
        title: 'Price you paid (₹/L)',
        points: points,
        formatValue: (v) => '₹${v.toStringAsFixed(2)}',
        emptyMessage: 'Appears once fill-ups carry a price.',
        controls: diff == null
            ? null
            : Text(
                diff.abs() < 0.005
                    ? 'Same as a year earlier'
                    : '${diff > 0 ? 'Up' : 'Down'} ₹${diff.abs().toStringAsFixed(2)} '
                        'on the same months a year earlier',
                style: TextStyle(color: colors.textSecondary, fontSize: 13)),
      ),
    ];
  }

  /// Km/L per pump, brand first, ranked by km/L or by ₹ per km.
  List<Widget> _pumpCard(AppColors colors) {
    final window = logsInRange(_chrono, _range.from, _range.to);
    final r = calculateGroupedEfficiency(window, (l) => l.pumpId ?? '',
        emptyKeyLabel: 'Unknown pump');
    // Litre-weighted price per pump, from fills that carry one.
    final spend = <String, double>{};
    final litres = <String, double>{};
    for (final l in window) {
      final p = l.pricePerLitre ?? computePricePerLitre(l.totalCost, l.liters);
      final key = l.pumpId ?? 'Unknown pump';
      if (p == null) continue;
      spend[key] = (spend[key] ?? 0) + p * l.liters;
      litres[key] = (litres[key] ?? 0) + l.liters;
    }
    final rows = [
      for (final g in r.rankings)
        () {
          final pump = _pumps[g.label];
          final price = (litres[g.label] ?? 0) > 0
              ? spend[g.label]! / litres[g.label]!
              : null;
          return _Ranked(
            title: pump?.brand ?? g.label,
            logo: pump?.brand ?? g.label,
            place: pump != null && pump.name.isNotEmpty ? pump.name : null,
            kmL: g.weightedEfficiency,
            price: price,
            fills: g.fillCount,
          );
        }(),
    ];
    return [
      const SizedBox(height: 14),
      _rankCard(
        colors,
        caption: 'Pump comparison',
        rows: rows,
        byCost: _pumpByCost,
        onByCost: (v) => setState(() => _pumpByCost = v),
      ),
    ];
  }

  /// A ranked comparison: by km/L (higher first) or by ₹ per km (lower
  /// first, rows without a price last), the leader in the primary colour.
  Widget _rankCard(
    AppColors colors, {
    required String caption,
    required List<_Ranked> rows,
    required bool byCost,
    required ValueChanged<bool> onByCost,
    Widget? period,
    String? footnote,
  }) {
    final sorted = [...rows]..sort((a, b) => byCost
        ? (a.perKm ?? double.infinity).compareTo(b.perKm ?? double.infinity)
        : b.kmL.compareTo(a.kmL));
    final bestKmL = rows.isEmpty ? 0.0 : rows.map((r) => r.kmL).reduce(math.max);
    final costs = rows.map((r) => r.perKm).whereType<double>();
    final bestCost = costs.isEmpty ? null : costs.reduce(math.min);
    final strong = TextStyle(
        color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600);
    final muted = TextStyle(color: colors.textSecondary, fontSize: 12);
    return _card([
      Row(
        children: [
          Expanded(child: _cap(caption, colors)),
          if (sorted.isNotEmpty)
            Text.rich(TextSpan(
                text: 'Best: ',
                style: TextStyle(color: colors.textSecondary, fontSize: 13),
                children: [
                  TextSpan(
                      text: sorted.first.title,
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w600)),
                ])),
        ],
      ),
      const SizedBox(height: 10),
      PeriodSelector(
        months: byCost ? 1 : 0,
        options: const [0, 1],
        label: (v) => v == 0 ? 'km/L' : '₹ per km',
        onChanged: (v) => onByCost(v == 1),
      ),
      if (period != null) ...[const SizedBox(height: 8), period],
      const SizedBox(height: 14),
      if (sorted.isEmpty)
        Text('Appears once a full-tank segment closes in this period.',
            style: TextStyle(color: colors.textSecondary, fontSize: 13))
      else
        for (final r in sorted)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              children: [
                if (r.logo != null) ...[
                  BrandLogo(brandName: r.logo!, size: 32),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                              child: Text(r.title,
                                  overflow: TextOverflow.ellipsis,
                                  style: strong)),
                          Text(
                              byCost
                                  ? (r.perKm == null
                                      ? 'No price'
                                      : '₹${r.perKm!.toStringAsFixed(2)}/km')
                                  : '${r.kmL.toStringAsFixed(1)} km/L',
                              style: strong),
                        ],
                      ),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: byCost
                              ? (r.perKm == null || bestCost == null
                                  ? 0
                                  : bestCost / r.perKm!)
                              : (bestKmL > 0 ? r.kmL / bestKmL : 0),
                          minHeight: 6,
                          color: identical(r, sorted.first)
                              ? colors.primary
                              : colors.primarySoft,
                          backgroundColor: colors.cardBorder,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                          [
                            ?r.place,
                            byCost
                                ? '${r.kmL.toStringAsFixed(1)} km/L'
                                : (r.perKm == null
                                    ? null
                                    : '₹${r.perKm!.toStringAsFixed(2)}/km'),
                            if (r.price != null)
                              '₹${r.price!.toStringAsFixed(2)}/L',
                            '${r.fills} ${r.fills == 1 ? 'refill' : 'refills'}',
                          ].whereType<String>().join(' · '),
                          style: muted),
                    ],
                  ),
                ),
              ],
            ),
          ),
      if (footnote != null) Text(footnote, style: muted),
    ]);
  }
  // ── Service ─────────────────────────────────────────────────────────

  List<Widget> _serviceCards(AppColors colors) {
    if (_services.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.only(top: 60),
          child: Text('No services yet. Log one on the Service tab.',
              textAlign: TextAlign.center,
              style: TextStyle(color: colors.textSecondary, fontSize: 14)),
        ),
      ];
    }
    final muted = TextStyle(color: colors.textSecondary, fontSize: 13);
    final strong = TextStyle(
        color: colors.textPrimary, fontSize: 15, fontWeight: FontWeight.w600);

    // Spend per month in the period.
    final bars = _monthly([
      for (final s in _services)
        if (s.cost != null) (s.timestamp, s.cost!),
    ]);
    final windowSpend = bars.fold<double>(0, (a, b) => a + b.$2);

    // A visit's cost split evenly across the types done.
    final byType = <String, double>{};
    for (final s in _services) {
      final cost = s.cost;
      if (cost == null || s.typeIds.isEmpty) continue;
      for (final id in s.typeIds) {
        final name = _types[id]?.name ?? 'Service';
        byType[name] = (byType[name] ?? 0) + cost / s.typeIds.length;
      }
    }
    final typeRows = byType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final topType = typeRows.isEmpty ? 0.0 : typeRows.first.value;

    // Running cost per km over everything driven.
    final fuelPerKm = calculateCostStats(_chrono, now: _now).costPerKm;
    final readings = [
      for (final l in _chrono) l.odometer,
      for (final s in _services) s.odometer,
    ];
    final span = readings.length < 2
        ? 0
        : readings.reduce(math.max) - readings.reduce(math.min);
    final serviceSpend =
        _services.fold<double>(0, (a, s) => a + (s.cost ?? 0));
    final servicePerKm = span > 0 ? serviceSpend / span : null;

    final upcoming = openSchedules(_services)
        .map((r) => nextServiceFor([r], _odometer, now: _now))
        .whereType<NextService>()
        .toList()
      ..sort((a, b) => (a.kmLeft ?? a.daysLeft! * 30)
          .compareTo(b.kmLeft ?? b.daysLeft! * 30));

    String perKm(double? v) => v == null ? '—' : '₹${v.toStringAsFixed(2)}';

    return [
      _card([
        _head('Service spend', '₹${_grouped.format(windowSpend)}', colors),
        const SizedBox(height: 12),
        _monthChart(bars),
      ]),
      if (typeRows.isNotEmpty) ...[
        const SizedBox(height: 14),
        _card([
          _cap('Spend by service type', colors),
          const SizedBox(height: 12),
          for (final e in typeRows)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(e.key, style: strong)),
                      Text('₹${_grouped.format(e.value)}', style: strong),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: topType > 0 ? e.value / topType : 0,
                      minHeight: 6,
                      color: colors.primarySoft,
                      backgroundColor: colors.cardBorder,
                    ),
                  ),
                ],
              ),
            ),
        ]),
      ],
      const SizedBox(height: 14),
      _card([
        _cap('Running cost per km', colors),
        const SizedBox(height: 12),
        for (final (label, v) in [
          ('Fuel', fuelPerKm),
          ('Service', servicePerKm),
          (
            'Total',
            fuelPerKm == null && servicePerKm == null
                ? null
                : (fuelPerKm ?? 0) + (servicePerKm ?? 0)
          ),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              children: [
                Expanded(
                    child: Text(label,
                        style: label == 'Total' ? strong : muted.copyWith(fontSize: 15))),
                Text(perKm(v), style: strong),
              ],
            ),
          ),
      ]),
      if (upcoming.isNotEmpty) ...[
        const SizedBox(height: 14),
        _card([
          _cap('Upcoming', colors),
          const SizedBox(height: 12),
          for (final n in upcoming)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                      child: Text(serviceTypeNames(n.record, _types),
                          style: TextStyle(
                              color: colors.textPrimary, fontSize: 15))),
                  Text(dueText(n),
                      style: TextStyle(
                          color: n.overdue ? colors.danger : colors.textSecondary,
                          fontSize: 14)),
                ],
              ),
            ),
        ]),
      ],
    ];
  }
  List<Widget> _gradeCard(AppColors colors) {
    final r = calculateFuelTypeEfficiency(
        logsInRange(_chrono, _range.from, _range.to));
    if (r.rankings.isEmpty) return const [];
    return [
      const SizedBox(height: 14),
      _rankCard(
        colors,
        caption: 'Fuel grade comparison',
        rows: [
          for (final g in r.rankings)
            _Ranked(
              title: g.fuelType,
              kmL: g.weightedEfficiency,
              price: g.avgPricePerLitre,
              fills: g.fillCount,
              perKmOverride: g.costPerKm,
            ),
        ],
        byCost: _gradeByCost,
        onByCost: (v) => setState(() => _gradeByCost = v),
      ),
    ];
  }
  Widget _totalsCard(AppColors colors) {
    final inPeriod = [for (final l in _chrono) if (_inRange(l.timestamp)) l];
    final spend = inPeriod.fold<double>(
        0,
        (s, l) =>
            s + (l.totalCost ?? computeTotalCost(l.pricePerLitre, l.liters) ?? 0));
    final distance = inPeriod.length < 2
        ? 0
        : inPeriod.map((l) => l.odometer).reduce(math.max) -
            inPeriod.map((l) => l.odometer).reduce(math.min);
    final litres = inPeriod.fold<double>(0, (s, l) => s + l.liters);
    Widget figure(String cap, String value) => Expanded(
          child: Column(
            children: [
              _cap(cap, colors),
              const SizedBox(height: 2),
              FittedBox(
                child: Text(value,
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        );
    return _card([
      Row(
        children: [
          figure('Spend', '₹${_grouped.format(spend)}'),
          figure('Distance', '${_grouped.format(distance)} km'),
          figure('Litres', '${litres.toStringAsFixed(1)} L'),
        ],
      ),
      const SizedBox(height: 8),
      Text(_period.kind == PeriodKind.overall ? 'All time' : _periodLabel,
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.textSecondary, fontSize: 12)),
    ]);
  }
}

/// One row of a ranked comparison.
class _Ranked {
  final String title;
  final String? logo;
  final String? place;
  final double kmL;

  /// Average ₹ a litre over the fills that have a price.
  final double? price;
  final int fills;
  final double? perKmOverride;

  const _Ranked({
    required this.title,
    this.logo,
    this.place,
    required this.kmL,
    this.price,
    required this.fills,
    this.perKmOverride,
  });

  double? get perKm =>
      perKmOverride ?? (price != null && kmL > 0 ? price! / kmL : null);
}

/// A custom period: quick picks (this month, the last 3 or 6 months, the
/// April to March financial years) or any From and To dates.
class _CustomRangeSheet extends StatefulWidget {
  final DateTime now;
  final AnalyticsPeriod current;

  const _CustomRangeSheet({required this.now, required this.current});

  @override
  State<_CustomRangeSheet> createState() => _CustomRangeSheetState();
}

class _CustomRangeSheetState extends State<_CustomRangeSheet> {
  late final DateTime _today =
      DateTime(widget.now.year, widget.now.month, widget.now.day);
  late DateTime _from = widget.current.kind == PeriodKind.custom
      ? widget.current.from!
      : DateTime(_today.year, _today.month - 2);
  late DateTime _to =
      widget.current.kind == PeriodKind.custom ? widget.current.to! : _today;

  List<(String, DateTime, DateTime)> get _picks {
    final fyStart = _today.month >= 4 ? _today.year : _today.year - 1;
    String fy(int y) => 'FY $y-${'${y + 1}'.substring(2)}';
    return [
      ('This month', DateTime(_today.year, _today.month), _today),
      ('Last 3 months', DateTime(_today.year, _today.month - 2), _today),
      ('Last 6 months', DateTime(_today.year, _today.month - 5), _today),
      (fy(fyStart), DateTime(fyStart, 4), _today),
      (fy(fyStart - 1), DateTime(fyStart - 1, 4), DateTime(fyStart, 3, 31)),
    ];
  }

  Future<void> _pick(bool from) async {
    final d = await showDatePicker(
      context: context,
      initialDate: from ? _from : _to,
      firstDate: DateTime(2000),
      lastDate: _today,
    );
    if (d != null) setState(() => from ? _from = d : _to = d);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final shown = DateFormat('d MMM y');
    final valid = !_from.isAfter(_to);
    Widget field(String label, DateTime v, bool from) => Expanded(
          child: InkWell(
            onTap: () => _pick(from),
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: InputDecoration(
                  labelText: label,
                  prefixIcon: const Icon(Icons.event_outlined)),
              child: Text(shown.format(v),
                  style: TextStyle(color: colors.textPrimary, fontSize: 15)),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Custom range',
              style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final (label, f, t) in _picks)
                ChoiceChip(
                  label: Text(label),
                  selected: _from == f && _to == t,
                  onSelected: (_) => setState(() {
                    _from = f;
                    _to = t;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              field('From', _from, true),
              const SizedBox(width: 10),
              field('To', _to, false),
            ],
          ),
          if (!valid)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('From must be on or before To',
                  style: TextStyle(color: colors.danger, fontSize: 12)),
            ),
          const SizedBox(height: 16),
          SizedBox(
            height: 50,
            child: ElevatedButton(
              onPressed: valid
                  ? () => Navigator.pop(context,
                      AnalyticsPeriod(PeriodKind.custom, from: _from, to: _to))
                  : null,
              child: const Text('Show'),
            ),
          ),
        ],
      ),
    );
  }
}
