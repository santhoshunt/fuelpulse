import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../db/database_helper.dart';
import '../models/fuel_log.dart';
import '../models/vehicle.dart';
import '../theme/app_colors.dart';
import '../utils/cost_calculator.dart';
import '../utils/efficiency_calculator.dart';
import '../utils/period_filter.dart';
import '../utils/trend_calculator.dart';
import '../utils/vehicle_manager.dart';
import '../widgets/brand_logo.dart';
import '../widgets/month_bar_chart.dart';
import '../widgets/period_selector.dart';
import '../widgets/trend_chart.dart';

final _grouped = NumberFormat('#,##,##0', 'en_IN');

/// The Analytics tab for the active vehicle: monthly fuel spend, mileage
/// over time, brand and fuel grade comparisons, and totals. Each chart
/// card picks its own period. Vehicles are never mixed: one vehicle's km/L
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
  int _spendMonths = 6;
  int _mileageMonths = 6;
  int _brandMonths = 6;

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
    if (!mounted) return;
    setState(() {
      _vehicle = vehicle;
      _chrono = chrono;
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
                  Text('Analytics',
                      style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 34,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5)),
                  Text(_vehicle?.name ?? '',
                      style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 15,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 14),
                  if (_chrono.isEmpty)
                    _notEnough(colors)
                  else ...[
                    _spendCard(colors),
                    const SizedBox(height: 14),
                    _mileageCard(),
                    ..._brandCard(colors),
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

  Widget _spendCard(AppColors colors) {
    final start = periodStart(_spendMonths, now: _now);
    final bars = <(DateTime, double)>[
      for (var i = 0; i < _spendMonths; i++)
        (DateTime(start.year, start.month + i), 0.0),
    ];
    for (final log in _chrono) {
      final at = DateTime.tryParse(log.timestamp);
      final spend =
          log.totalCost ?? computeTotalCost(log.pricePerLitre, log.liters);
      if (at == null || spend == null || at.isBefore(start)) continue;
      final i = (at.year - start.year) * 12 + at.month - start.month;
      if (i < bars.length) bars[i] = (bars[i].$1, bars[i].$2 + spend);
    }
    final total = bars.fold<double>(0, (s, b) => s + b.$2);
    return _card([
      _head('Fuel expenses', '₹${_grouped.format(total)}', colors),
      const SizedBox(height: 10),
      PeriodSelector(
          months: _spendMonths,
          options: const [1, 3, 6, 12],
          onChanged: (m) => setState(() => _spendMonths = m)),
      const SizedBox(height: 12),
      MonthBarChart(bars: bars, formatValue: (v) => '₹${_grouped.format(v)}'),
    ]);
  }

  Widget _mileageCard() {
    final start = periodStart(_mileageMonths, now: _now);
    final trend = calculateSegmentTrend(_chrono)
        .where((p) => !p.closedAt.isBefore(start))
        .toList();
    return TrendChart(
      title: 'Fuel mileage (km/L)',
      points: trend.map((p) => TrendPoint(p.closedAt, p.kmPerLitre)).toList(),
      formatValue: (v) => v.toStringAsFixed(1),
      emptyMessage: 'Trend appears after 2 completed full-tank segments.',
      controls: PeriodSelector(
          months: _mileageMonths,
          options: const [1, 3, 6, 12],
          onChanged: (m) => setState(() => _mileageMonths = m)),
    );
  }

  List<Widget> _brandCard(AppColors colors) {
    final r = calculateBrandEfficiency(
        logsInLastMonths(_chrono, _brandMonths, now: _now));
    final best = r.rankings.isEmpty ? 0.0 : r.rankings.first.weightedEfficiency;
    return [
      const SizedBox(height: 14),
      _card([
        Row(
          children: [
            Expanded(child: _cap('Brand comparison', colors)),
            if (r.bestBrand != null)
              Text.rich(TextSpan(
                  text: 'Best: ',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                  children: [
                    TextSpan(
                        text: r.bestBrand,
                        style: TextStyle(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w600)),
                  ])),
          ],
        ),
        const SizedBox(height: 10),
        PeriodSelector(
            months: _brandMonths,
            options: const [3, 6, 12],
            onChanged: (m) => setState(() => _brandMonths = m)),
        const SizedBox(height: 14),
        if (r.rankings.isEmpty)
          Text('Appears once a full-tank segment closes in this period.',
              style: TextStyle(color: colors.textSecondary, fontSize: 13))
        else
          for (final b in r.rankings)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  BrandLogo(brandName: b.brand, size: 32),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(b.brand.isEmpty ? 'Unknown' : b.brand,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      color: colors.textPrimary,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                            ),
                            Text('${b.weightedEfficiency.toStringAsFixed(1)} km/L',
                                style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: best > 0
                                ? math.min(1.0, b.weightedEfficiency / best)
                                : 0,
                            minHeight: 6,
                            color: b.weightedEfficiency == best
                                ? colors.primary
                                : colors.primarySoft,
                            backgroundColor: colors.cardBorder,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                            '${b.fillCount} ${b.fillCount == 1 ? 'refill' : 'refills'}',
                            style: TextStyle(
                                color: colors.textSecondary, fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
      ]),
    ];
  }

  List<Widget> _gradeCard(AppColors colors) {
    final r = calculateFuelTypeEfficiency(_chrono);
    if (r.rankings.isEmpty) return const [];
    return [
      const SizedBox(height: 14),
      _card([
        _cap('Fuel grade comparison', colors),
        const SizedBox(height: 12),
        for (final g in r.rankings)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text.rich(TextSpan(
                    text: g.fuelType,
                    style: TextStyle(color: colors.textPrimary, fontSize: 15),
                    children: [
                      TextSpan(
                          text:
                              ' · ${g.fillCount} ${g.fillCount == 1 ? 'refill' : 'refills'}',
                          style: TextStyle(
                              color: colors.textSecondary, fontSize: 13)),
                    ],
                  )),
                ),
                Text('${g.weightedEfficiency.toStringAsFixed(1)} km/L',
                    style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        Text('All time',
            style: TextStyle(color: colors.textSecondary, fontSize: 12)),
      ]),
    ];
  }

  Widget _totalsCard(AppColors colors) {
    final cost = calculateCostStats(_chrono, now: _now);
    final distance = _chrono.length < 2
        ? 0
        : _chrono.map((l) => l.odometer).reduce(math.max) -
            _chrono.map((l) => l.odometer).reduce(math.min);
    final litres = _chrono.fold<double>(0, (s, l) => s + l.liters);
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
          figure('Spend', '₹${_grouped.format(cost.totalSpend)}'),
          figure('Distance', '${_grouped.format(distance)} km'),
          figure('Litres', '${litres.toStringAsFixed(1)} L'),
        ],
      ),
      const SizedBox(height: 8),
      Text('All time',
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.textSecondary, fontSize: 12)),
    ]);
  }
}
