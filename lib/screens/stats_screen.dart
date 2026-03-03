import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../utils/constants.dart';
import '../utils/efficiency_calculator.dart';
import '../widgets/brand_rank_tile.dart';
import '../widgets/stat_card.dart';

class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});

  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  final _db = DatabaseHelper();
  BrandComparisonResult? _result;
  bool _loading = true;
  bool _hasEnoughData = false;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    final chrono = await _db.getAllLogsChrono();
    final result = calculateBrandEfficiency(chrono);

    // Check if there's at least 1 completed segment
    final hasSegments = result.totalKm > 0 && result.totalLiters > 0;

    setState(() {
      _result = result;
      _hasEnoughData = hasSegments;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistics'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_hasEnoughData
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

  Widget _buildStats(Color accent) {
    final r = _result!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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

          // Brand ranking header
          const Text(
            'Brand Ranking',
            style: TextStyle(
              color: kTextPrimary,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),

          // Brand ranking list
          if (r.rankings.isEmpty)
            const Text('No brand data available.',
                style: TextStyle(color: kTextMuted))
          else
            ...r.rankings.asMap().entries.map((e) {
              final idx = e.key;
              final brand = e.value;
              return BrandRankTile(
                rank: idx + 1,
                brand: brand.brand,
                fillCount: brand.fillCount,
                totalLiters: brand.totalLiters,
                efficiency: brand.weightedEfficiency,
                bestEfficiency: r.rankings.first.weightedEfficiency,
                deltaVsOverall: brand.deltaVsOverall,
              );
            }),
        ],
      ),
    );
  }
}
