import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show NumberFormat;

import '../db/database_helper.dart';
import '../models/fuel_log.dart';
import '../models/pump.dart';
import '../models/service_record.dart';
import '../models/service_type.dart';
import '../models/vehicle.dart';
import '../theme/app_colors.dart';
import '../utils/cost_calculator.dart';
import '../utils/efficiency_calculator.dart';
import '../utils/period_filter.dart';
import '../utils/service_schedule.dart';
import '../utils/trend_calculator.dart';
import '../utils/vehicle_manager.dart';
import '../widgets/brand_logo.dart';
import '../widgets/month_bar_chart.dart';
import '../widgets/period_selector.dart';
import '../widgets/trend_chart.dart';
import 'service_screen.dart' show dueText, latestOdometer, serviceTypeNames;

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
  int _serviceMonths = 12;
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

  /// Km/L per pump, brand first, the best in the primary colour.
  List<Widget> _pumpCard(AppColors colors) {
    final r = calculateGroupedEfficiency(
        logsInLastMonths(_chrono, _brandMonths, now: _now),
        (l) => l.pumpId ?? '',
        emptyKeyLabel: 'Unknown pump');
    final best = r.rankings.isEmpty ? 0.0 : r.rankings.first.weightedEfficiency;
    final bestPump = r.rankings.isEmpty ? null : _pumps[r.rankings.first.label];
    return [
      const SizedBox(height: 14),
      _card([
        Row(
          children: [
            Expanded(child: _cap('Pump comparison', colors)),
            if (r.rankings.isNotEmpty)
              Text.rich(TextSpan(
                  text: 'Best: ',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                  children: [
                    TextSpan(
                        text: bestPump?.brand ?? r.rankings.first.label,
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
          for (final g in r.rankings) _pumpRow(g, best, colors),
      ]),
    ];
  }

  Widget _pumpRow(GroupEfficiency g, double best, AppColors colors) {
    final pump = _pumps[g.label];
    final brand = pump?.brand ?? g.label;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          BrandLogo(brandName: brand, size: 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(brand,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                    ),
                    Text('${g.weightedEfficiency.toStringAsFixed(1)} km/L',
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
                        ? math.min(1.0, g.weightedEfficiency / best)
                        : 0,
                    minHeight: 6,
                    color: g.weightedEfficiency == best
                        ? colors.primary
                        : colors.primarySoft,
                    backgroundColor: colors.cardBorder,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                    [
                      if (pump != null && pump.name.isNotEmpty) pump.name,
                      '${g.fillCount} ${g.fillCount == 1 ? 'refill' : 'refills'}',
                    ].join(' · '),
                    style:
                        TextStyle(color: colors.textSecondary, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
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

    // Spend per month in the window.
    final start = periodStart(_serviceMonths, now: _now);
    final bars = <(DateTime, double)>[
      for (var i = 0; i < _serviceMonths; i++)
        (DateTime(start.year, start.month + i), 0.0),
    ];
    for (final s in _services) {
      final at = DateTime.tryParse(s.timestamp);
      if (at == null || s.cost == null || at.isBefore(start)) continue;
      final i = (at.year - start.year) * 12 + at.month - start.month;
      if (i < bars.length) bars[i] = (bars[i].$1, bars[i].$2 + s.cost!);
    }
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
        const SizedBox(height: 10),
        PeriodSelector(
            months: _serviceMonths,
            options: const [3, 6, 12],
            onChanged: (m) => setState(() => _serviceMonths = m)),
        const SizedBox(height: 12),
        MonthBarChart(
            bars: bars, formatValue: (v) => '₹${_grouped.format(v)}'),
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
