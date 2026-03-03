import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/fuel_log.dart';
import '../utils/constants.dart';
import '../utils/efficiency_calculator.dart';
import 'brand_badge.dart';
import 'glossy_card.dart';

/// Single log row/card in the home list.
class FuelLogTile extends StatelessWidget {
  final FuelLog log;
  final int? distanceToNext;
  final EfficiencyResult? efficiency;
  final double? tankLevel;
  final double tankCapacity;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const FuelLogTile({
    super.key,
    required this.log,
    this.distanceToNext,
    this.efficiency,
    this.tankLevel,
    required this.tankCapacity,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final dateStr = _formatDate(log.timestamp);
    final effStr = _efficiencyString();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: GlossyCard(
            padding: const EdgeInsets.all(14),
            borderRadius: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: date, brand, actions
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dateStr,
                            style: const TextStyle(
                              color: kTextSecondary,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              BrandBadge(brandName: log.pumpBrand, size: 26),
                              const SizedBox(width: 10),
                              _fullPartialTag(),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.edit_outlined,
                          color: accent.withValues(alpha: 0.7), size: 20),
                      onPressed: onEdit,
                      visualDensity: VisualDensity.compact,
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          color: kDanger.withValues(alpha: 0.7), size: 20),
                      onPressed: onDelete,
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Data row
                Wrap(
                  spacing: 14,
                  runSpacing: 6,
                  children: [
                    _dataChip(Icons.speed, '${log.odometer} km'),
                    _dataChip(Icons.local_gas_station, '${log.liters.toStringAsFixed(1)} L'),
                    if (distanceToNext != null)
                      _dataChip(Icons.straighten, '$distanceToNext km'),
                    if (tankLevel != null && tankCapacity > 0)
                      _dataChip(Icons.propane_tank_outlined,
                          '~${tankLevel!.toStringAsFixed(1)} L in tank'),
                  ],
                ),
                const SizedBox(height: 8),
                // Efficiency + segment breakdown
                Row(
                  children: [
                    Icon(Icons.analytics_outlined,
                        size: 14, color: kTextSecondary),
                    const SizedBox(width: 4),
                    Text(
                      effStr,
                      style: TextStyle(
                        color: efficiency?.value != null ? accent : kTextMuted,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (efficiency?.segmentDistance != null &&
                        efficiency?.segmentLiters != null) ...[  
                      const SizedBox(width: 8),
                      Text(
                        '(${efficiency!.segmentDistance!.toStringAsFixed(0)} km ÷ ${efficiency!.segmentLiters!.toStringAsFixed(1)} L)',
                        style: const TextStyle(
                          color: kTextMuted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ],
                ),
                // Notes
                if (log.notes.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(
                    log.notes,
                    style: const TextStyle(
                      color: kTextMuted,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
      ),
    );
  }

  Widget _fullPartialTag() {
    final isFull = log.fullTank;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: (isFull ? const Color(0xFFFFD60A) : const Color(0xFFF59E0B))
            .withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        isFull ? 'FULL' : 'PARTIAL',
        style: TextStyle(
          color: isFull ? const Color(0xFFFFD60A) : const Color(0xFFF59E0B),
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _dataChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: kTextMuted),
        const SizedBox(width: 3),
        Text(
          text,
          style: const TextStyle(color: kTextSecondary, fontSize: 12),
        ),
      ],
    );
  }

  String _efficiencyString() {
    if (efficiency == null) return '—';
    if (efficiency!.isPending) return 'pending';
    if (efficiency!.value != null) {
      return '${efficiency!.value!.toStringAsFixed(1)} km/L';
    }
    return '—';
  }

  String _formatDate(String isoTimestamp) {
    try {
      final dt = DateTime.parse(isoTimestamp);
      return DateFormat('dd MMM yyyy, hh:mm a').format(dt);
    } catch (_) {
      return isoTimestamp;
    }
  }
}
