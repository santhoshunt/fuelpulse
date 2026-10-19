import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/vehicle.dart';
import '../utils/constants.dart';
import '../utils/cost_calculator.dart';
import '../utils/efficiency_calculator.dart';
import '../utils/trend_calculator.dart';
import '../widgets/brand_badge.dart';
import '../widgets/rank_tile.dart';
import '../widgets/stat_card.dart';
import '../widgets/trend_chart.dart';

class StatsScreen extends StatefulWidget {
  /// Statistics never mix vehicles: one vehicle's km/L next to another's
  /// would average into a meaningless number.
  final Vehicle vehicle;

  const StatsScreen({super.key, required this.vehicle});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final _db = DatabaseHelper();
  BrandComparisonResult? _result;
  FuelTypeComparisonResult? _fuelTypeResult;
  CostStats? _costStats;
  List<SegmentTrendPoint> _trend = const [];
  int _logCount = 0;
  bool _loading = true;
  bool _hasSegments = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final chrono = await _db.getAllLogsChrono(widget.vehicle.id);
    final result = calculateBrandEfficiency(chrono);
    final fuelTypeResult = calculateFuelTypeEfficiency(chrono);
    final costStats = calculateCostStats(chrono);
    final trend = calculateSegmentTrend(chrono);

    // Check if there's at least 1 completed segment
    final hasSegments = result.totalKm > 0 && result.totalLiters > 0;

    if (!mounted) return;
    setState(() {
      _result = result;
      _fuelTypeResult = fuelTypeResult;
      _costStats = costStats;
      _trend = trend;
      _logCount = chrono.length;
      _hasSegments = hasSegments;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: Text('Statistics · ${widget.vehicle.name}',
            overflow: TextOverflow.ellipsis),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          // Cost data can exist before any completed efficiency segment,
          // so the page shows whenever either has something to render.
          : !_hasSegments && (_costStats?.totalSpend ?? 0) <= 0
              ? _buildNotEnoughData()
              : _buildStats(accent),
    );
  }

  Widget _buildNotEnoughData() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.bar_chart_outlined,
                size: 64, color: kTextMuted.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            const Text(
              'Not enough data',
              style: TextStyle(
                color: kTextSecondary,
                fontSize: 18,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Need at least 2 fill-ups with a completed full-tank segment to show stats.',
              textAlign: TextAlign.center,
              style: TextStyle(color: kTextMuted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, Color accent) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            color: kTextPrimary,
            fontSize: 18,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.2,
          ),
        ),
      ],
    );
  }

  Widget _buildStats(Color accent) {
    final r = _result!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_hasSegments) ...[
          // 2×2 summary grid
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: StatCard(
                    emoji: '🏆',
                    label: 'Best Performance',
                    value: r.bestBrand ?? '—',
                    subtitle: r.bestEfficiency != null
                        ? '${r.bestEfficiency!.toStringAsFixed(1)} km/L'
                        : null,
                    borderColor: accent.withValues(alpha: 0.4),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatCard(
                    emoji: '⚠️',
                    label: r.worstBrand != null
                        ? 'Worst Performance'
                        : 'Overall',
                    value: r.worstBrand ?? '${r.overallEfficiency.toStringAsFixed(1)} km/L',
                    subtitle: r.worstEfficiency != null
                        ? '${r.worstEfficiency!.toStringAsFixed(1)} km/L'
                        : null,
                    borderColor: kDanger.withValues(alpha: 0.3),
                    backgroundColor: kDanger.withValues(alpha: 0.05),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: StatCard(
                    emoji: '📊',
                    label: 'Overall Average',
                    value: '${r.overallEfficiency.toStringAsFixed(1)} km/L',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: StatCard(
                    emoji: '📏',
                    label: 'Total Tracked',
                    value: '${r.totalKm.toStringAsFixed(0)} km',
                    subtitle: '${r.totalLiters.toStringAsFixed(0)} L used',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Trends ────────────────────────────────────
          _sectionHeader('Trends', accent),
          const SizedBox(height: 6),
          const Text(
            'Each point is one full-tank to full-tank segment.',
            style: TextStyle(color: kTextMuted, fontSize: 12),
          ),
          const SizedBox(height: 14),
          TrendChart(
            title: 'Efficiency (km/L)',
            points: _trend
                .map((p) => TrendPoint(p.closedAt, p.kmPerLitre))
                .toList(),
            formatValue: (v) => v.toStringAsFixed(1),
            emptyMessage: 'Trend appears after 2 completed full-tank segments.',
          ),
          const SizedBox(height: 12),
          TrendChart(
            title: 'Cost per km (₹)',
            points: _trend
                .where((p) => p.costPerKm != null)
                .map((p) => TrendPoint(p.closedAt, p.costPerKm!))
                .toList(),
            formatValue: (v) => '₹${v.toStringAsFixed(2)}',
            // With fewer than 2 segments, missing prices are not the reason.
            emptyMessage: _trend.length < 2
                ? 'Trend appears after 2 completed full-tank segments.'
                : 'Add price or total to fill-ups to see cost per km over time.',
          ),
          const SizedBox(height: 28),
          ],

          // ── Cost analytics ────────────────────────────
          if ((_costStats?.totalSpend ?? 0) > 0) ...[
            _sectionHeader('Cost Analytics', accent),
            const SizedBox(height: 14),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: StatCard(
                      emoji: '💰',
                      label: 'Total Spend',
                      value: '₹${formatMoney(_costStats!.totalSpend)}',
                      subtitle:
                          '${_costStats!.costLogCount} of $_logCount fill-ups have cost',
                      borderColor: accent.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      emoji: '⛽',
                      label: 'Avg Price',
                      value: _costStats!.avgPricePerLitre != null
                          ? '₹${_costStats!.avgPricePerLitre!.toStringAsFixed(2)}/L'
                          : '—',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: StatCard(
                      emoji: '🛣️',
                      label: 'Cost per km',
                      value: _costStats!.costPerKm != null
                          ? '₹${_costStats!.costPerKm!.toStringAsFixed(2)}/km'
                          : '—',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: StatCard(
                      emoji: '📅',
                      label: 'This Month',
                      value: '₹${formatMoney(_costStats!.monthSpend)}',
                      subtitle: _costStats!.avgMonthlySpend != null
                          ? 'avg ₹${formatMoney(_costStats!.avgMonthlySpend!)}/month'
                          : null,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 28),
          ],

          if (_hasSegments) ...[
          // Brand ranking header
          _sectionHeader('Brand Ranking', accent),
          const SizedBox(height: 14),

          // Brand ranking list
          if (r.rankings.isEmpty)
            const Text('No brand data available.',
                style: TextStyle(color: kTextMuted))
          else
            ...r.rankings.asMap().entries.map((e) {
              final idx = e.key;
              final brand = e.value;
              return RankTile(
                rank: idx + 1,
                label: brand.brand,
                leading: BrandBadge(
                    brandName: brand.brand, showLabel: true, size: 28),
                fillCount: brand.fillCount,
                totalLiters: brand.totalLiters,
                efficiency: brand.weightedEfficiency,
                bestEfficiency: r.rankings.first.weightedEfficiency,
                deltaVsOverall: brand.deltaVsOverall,
              );
            }),
          ],

          // ── Fuel type ranking ─────────────────────────
          // One fuel type means nothing to compare, so the section only
          // appears once a second type has completed segments.
          if (_hasSegments &&
              (_fuelTypeResult?.rankings.length ?? 0) >= 2) ...[
            const SizedBox(height: 18),
            _sectionHeader('Fuel Type Ranking', accent),
            const SizedBox(height: 14),
            ..._fuelTypeResult!.rankings.asMap().entries.map((e) {
              final idx = e.key;
              final ft = e.value;
              return RankTile(
                rank: idx + 1,
                label: ft.fuelType,
                leading: _fuelTypeLabel(ft.fuelType, accent),
                fillCount: ft.fillCount,
                totalLiters: ft.totalLiters,
                efficiency: ft.weightedEfficiency,
                bestEfficiency:
                    _fuelTypeResult!.rankings.first.weightedEfficiency,
                deltaVsOverall: ft.deltaVsOverall,
                extraDetails: [
                  if (ft.avgPricePerLitre != null)
                    '₹${ft.avgPricePerLitre!.toStringAsFixed(2)}/L avg',
                  if (ft.costPerKm != null)
                    '₹${ft.costPerKm!.toStringAsFixed(2)}/km',
                ],
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _fuelTypeLabel(String fuelType, Color accent) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Icon(Icons.local_fire_department_outlined,
              size: 16, color: accent),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            fuelType,
            style: const TextStyle(color: kTextPrimary, fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
