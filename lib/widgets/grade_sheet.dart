import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat, NumberFormat;

import '../models/fuel_log.dart';
import '../models/vehicle.dart';
import '../theme/app_colors.dart';
import '../utils/cost_calculator.dart';
import '../utils/efficiency_calculator.dart';
import '../utils/mileage_bands.dart';
import 'brand_logo.dart';

/// What the user picked in the grade sheet.
enum GradeAction { open, edit, delete }

/// The grade chip a Fuel row shows: the combined grade word, "Partial", or
/// nothing yet.
Widget gradeChip(BuildContext context, FuelLog log, Vehicle vehicle,
    EfficiencyResult? eff) {
  final colors = AppColors.of(context);
  final kmL = eff?.value;
  final (text, color) = !log.fullTank
      ? ('Partial', colors.textSecondary)
      : kmL == null
          ? ((eff?.isPending ?? false) ? 'Pending' : '—', colors.textSecondary)
          : () {
              final g = gradeOf(vehicle, kmL, _price(log)).grade;
              return (
                MileageBands.names[g],
                bandColor(g, Theme.of(context).brightness)
              );
            }();
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
    decoration: BoxDecoration(
      border: Border.all(color: color),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(text,
        style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
  );
}

double? _price(FuelLog log) =>
    log.pricePerLitre ?? computePricePerLitre(log.totalCost, log.liters);

/// Slides up from a Fuel row: where the fill-up sits in the vehicle's km/L
/// and ₹/km ranges, why its grade is what it is, and what to do with it.
Future<GradeAction?> showGradeSheet(BuildContext context,
    {required FuelLog log, required Vehicle vehicle, EfficiencyResult? eff}) {
  return showModalBottomSheet<GradeAction>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => _GradeSheet(log: log, vehicle: vehicle, eff: eff),
  );
}

class _GradeSheet extends StatefulWidget {
  final FuelLog log;
  final Vehicle vehicle;
  final EfficiencyResult? eff;

  const _GradeSheet({required this.log, required this.vehicle, this.eff});

  @override
  State<_GradeSheet> createState() => _GradeSheetState();
}

class _GradeSheetState extends State<_GradeSheet> {
  /// How far a finger has dragged up, in pixels; past [_openAt] letting go
  /// opens the fill-up page. Read from raw pointer moves, so the sheet's own
  /// drag down to close and its buttons work as before.
  double _lift = 0;
  double? _downY;
  static const _openAt = 90.0;

  FuelLog get log => widget.log;
  Vehicle get vehicle => widget.vehicle;
  EfficiencyResult? get eff => widget.eff;

  void _released() {
    if (_lift >= _openAt) {
      Navigator.pop(context, GradeAction.open);
    } else if (_lift > 0) {
      setState(() => _lift = 0);
    }
    _downY = null;
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (e) => _downY = e.position.dy,
      onPointerMove: (e) {
        final up = (_downY ?? e.position.dy) - e.position.dy;
        setState(() => _lift = up > 0 ? up : 0);
      },
      onPointerUp: (_) => _released(),
      onPointerCancel: (_) {
        _downY = null;
        setState(() => _lift = 0);
      },
      child: AnimatedSlide(
        duration: const Duration(milliseconds: 120),
        offset: Offset(0, -(_lift.clamp(0, 140) / 140) * 0.08),
        child: _content(context),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final colors = AppColors.of(context);
    final b = Theme.of(context).brightness;
    final at = DateTime.tryParse(log.timestamp);
    final price = _price(log);
    final kmL = eff?.value;
    final g = kmL == null ? null : gradeOf(vehicle, kmL, price);
    final grouped = NumberFormat('#,##,##0', 'en_IN');
    final muted = TextStyle(color: colors.textSecondary, fontSize: 13);

    String reason() {
      if (!log.fullTank) {
        return 'A partial fill has no km/L of its own: it counts towards the '
            'next full tank.';
      }
      if (g == null) {
        return 'Rated once the next full tank shows how far this fuel went.';
      }
      final m = MileageBands.names[g.mileage];
      if (g.cost == null) {
        return 'Rated on mileage only: this fill-up has no price.';
      }
      final c = MileageBands.names[g.cost!];
      if (g.mileage == g.cost) return 'Mileage and cost per km are both $m.';
      return g.mileage > g.cost!
          ? 'The rating is the lower of the two: $m mileage, but $c on cost.'
          : 'The rating is the lower of the two: $c on cost, but $m mileage.';
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                BrandLogo(brandName: log.pumpBrand, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${log.pumpBrand.isEmpty ? 'Unknown' : log.pumpBrand} · ${log.fuelType}',
                          style: TextStyle(
                              color: colors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.w600)),
                      Text(
                          [
                            if (at != null) DateFormat('d MMM y').format(at),
                            '${grouped.format(log.odometer)} km',
                            '${log.liters.toStringAsFixed(2)} L',
                            if (price != null) '₹${price.toStringAsFixed(2)}/L',
                          ].join(' · '),
                          style: muted),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                gradeChip(context, log, vehicle, eff),
              ],
            ),
            if (g != null) ...[
              const SizedBox(height: 18),
              _Meter(
                label: 'Mileage',
                value: '${kmL!.toStringAsFixed(1)} km/L · '
                    '${MileageBands.names[g.mileage]}',
                band: g.mileage,
                brightness: b,
              ),
              if (g.cost != null) ...[
                const SizedBox(height: 14),
                _Meter(
                  label: 'Cost per km',
                  value: '₹${g.perKm!.toStringAsFixed(2)}/km · '
                      '${MileageBands.names[g.cost!]}',
                  band: g.cost!,
                  brightness: b,
                ),
              ],
            ],
            const SizedBox(height: 14),
            Text(reason(), style: muted),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, GradeAction.open),
                    child: const Text('Open fill-up'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, GradeAction.edit),
                  child: const Text('Edit'),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => Navigator.pop(context, GradeAction.delete),
                  style: OutlinedButton.styleFrom(foregroundColor: colors.danger),
                  child: const Text('Delete'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
                _lift >= _openAt
                    ? 'Release to open the fill-up'
                    : 'Swipe up for the full fill-up',
                textAlign: TextAlign.center,
                style: muted.copyWith(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

/// Five coloured segments with a marker on the fill-up's band.
class _Meter extends StatelessWidget {
  final String label;
  final String value;
  final int band;
  final Brightness brightness;

  const _Meter({
    required this.label,
    required this.value,
    required this.band,
    required this.brightness,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
                child: Text(label,
                    style: TextStyle(color: colors.textSecondary, fontSize: 13))),
            Text(value,
                style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < 5; i++)
              Expanded(
                child: Container(
                  height: i == band ? 12 : 7,
                  margin: const EdgeInsets.symmetric(horizontal: 1.5),
                  decoration: BoxDecoration(
                    color: bandColor(i, brightness)
                        .withValues(alpha: i == band ? 1 : 0.35),
                    borderRadius: BorderRadius.circular(3),
                    border: i == band
                        ? Border.all(color: colors.textPrimary, width: 1.5)
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
