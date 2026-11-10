import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/vehicle.dart';
import '../theme/app_colors.dart';
import '../utils/efficiency_calculator.dart';
import '../utils/gauge_scale.dart';
import '../utils/mileage_bands.dart';
import '../widgets/gauge_card.dart' show GaugeCard;
import '../widgets/period_selector.dart' show SlidingSegments;
import '../widgets/vehicle_picker.dart' show vehicleTypeLabel;

/// The five bands for one vehicle, by km/L or, with [cost], by ₹ per km: a
/// preview bar, one row per band, and a reset to the type's defaults. The
/// km/L screen also holds the Dashboard gauge's scale. Every change saves
/// as it is made, like the rest of Settings.
class MileageRangesScreen extends StatefulWidget {
  final Vehicle vehicle;

  /// Cost per km ranges: lower is better, so the limits run downwards.
  final bool cost;

  const MileageRangesScreen(
      {super.key, required this.vehicle, this.cost = false});

  @override
  State<MileageRangesScreen> createState() => _MileageRangesScreenState();
}

class _MileageRangesScreenState extends State<MileageRangesScreen> {
  late Vehicle _vehicle = widget.vehicle;
  late List<double> _limits = List.of(
      _cost ? costBandsFor(_vehicle).limits : bandsFor(_vehicle).limits);

  bool get _cost => widget.cost;

  /// Shows and saves new limits.
  Future<void> _saveLimits(List<double> limits) async {
    setState(() => _limits = limits);
    _vehicle = _cost
        ? _vehicle.copyWith(costBands: limits)
        : _vehicle.copyWith(mileageBands: limits);
    await DatabaseHelper().updateVehicle(_vehicle);
  }

  /// Shows and saves the gauge scale; null is Auto.
  Future<void> _saveScale((double, double)? scale) async {
    setState(() => _custom = scale);
    await saveGaugeScale(_vehicle.id, scale);
  }

  Future<void> _reset() async {
    final before = List.of(_limits);
    await _saveLimits(List.of(_cost
        ? defaultCostBandsFor(_vehicle.type).limits
        : defaultBandsFor(_vehicle.type).limits));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(
          'Reset to ${vehicleTypeLabel(_vehicle.type).toLowerCase()} defaults'),
      action:
          SnackBarAction(label: 'Undo', onPressed: () => _saveLimits(before)),
    ));
  }

  /// The gauge scale Auto gives today, and the custom one (null is Auto).
  (double, double)? _auto;
  (double, double)? _custom;

  bool get _hasGauge => !_cost;

  @override
  void initState() {
    super.initState();
    if (_hasGauge) _loadGauge();
  }

  Future<void> _loadGauge() async {
    final id = _vehicle.id;
    final chrono = await DatabaseHelper().getAllLogsChrono(id);
    final overall = calculateBrandEfficiency(chrono);
    final avg = overall.totalLiters > 0 ? overall.overallEfficiency : null;
    final values = [
      ...calculateEfficiency(chrono).values.map((e) => e.value).whereType<double>(),
      ?avg,
    ];
    final custom = await loadGaugeScale(id);
    if (!mounted) return;
    setState(() {
      _auto = GaugeCard.scaleFor(avg, values);
      _custom = custom;
    });
  }

  /// Asks for the gauge's From or To in km/L.
  Future<void> _editScale({required bool from}) async {
    final (lo, hi) = _custom ?? _auto ?? (0.0, 25.0);
    final controller = TextEditingController(text: _n(from ? lo : hi));
    String? error;
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(from ? 'Gauge starts at' : 'Gauge ends at'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration:
                InputDecoration(suffixText: 'km/L', errorText: error),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final v = double.tryParse(controller.text.trim());
                final ok = v != null && v >= 0 && (from ? v < hi : v > lo);
                if (!ok) {
                  setDialog(() => error = from
                      ? 'From 0 up to below ${_n(hi)}'
                      : 'More than ${_n(lo)}');
                  return;
                }
                Navigator.pop(ctx, v);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (value != null) await _saveScale(from ? (value, hi) : (lo, value));
  }

  Widget _gaugeCard(AppColors colors) {
    final shown = _custom ?? _auto;
    final muted = TextStyle(color: colors.textSecondary, fontSize: 13);
    Widget end(String label, double? v, bool from) => ListTile(
          contentPadding: EdgeInsets.zero,
          enabled: _custom != null,
          title: Text(label, style: TextStyle(color: colors.textPrimary)),
          trailing: Text(v == null ? '' : '${_n(v)} km/L ›', style: muted),
          onTap: () => _editScale(from: from),
        );
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('DASHBOARD GAUGE SCALE',
                style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 11,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            SlidingSegments(
              labels: const ['Auto', 'Custom'],
              selected: _custom == null ? 0 : 1,
              onTap: (i) =>
                  _saveScale(i == 0 ? null : (_auto ?? (0.0, 25.0))),
              background: Color.alphaBlend(
                  colors.textPrimary.withValues(alpha: 0.07), colors.page),
              height: 38,
            ),
            const SizedBox(height: 8),
            if (_custom == null)
              Text(
                  _auto == null
                      ? 'Fits the scale to your fill-ups.'
                      : 'Now ${_n(_auto!.$1)} to ${_n(_auto!.$2)} km/L, fitted '
                          'to your average and your best and worst fill-ups.',
                  style: muted),
            end('From', shown?.$1, true),
            end('To', shown?.$2, false),
          ],
        ),
      ),
    );
  }

  String _n(double v) {
    final s = v == v.roundToDouble()
        ? v.toStringAsFixed(0)
        : v.toStringAsFixed(_cost ? 2 : 1);
    return _cost ? '₹$s' : s;
  }

  String _range(int band) {
    final l = _limits;
    if (_cost) {
      return switch (band) {
        0 => 'above ${_n(l[0])}/km',
        4 => 'up to ${_n(l[3])}/km',
        _ => '${_n(l[band])} to ${_n(l[band - 1])}',
      };
    }
    return switch (band) {
      0 => 'below ${_n(l[0])} km/L',
      4 => '${_n(l[3])} and above',
      _ => '${_n(l[band - 1])} to ${_n(l[band])}',
    };
  }

  /// km/L: each band edits the limit it ends at; Great edits where it
  /// starts. ₹/km: each band edits the cost above which it applies; Great
  /// edits Good's.
  Future<void> _edit(int band) async {
    final i = band.clamp(0, 3);
    final double lo;
    final double hi;
    if (_cost) {
      lo = i == 3 ? 0.0 : _limits[i + 1];
      hi = i == 0 ? double.infinity : _limits[i - 1];
    } else {
      lo = i == 0 ? 0.0 : _limits[i - 1];
      hi = i == 3 ? double.infinity : _limits[i + 1];
    }
    final controller =
        TextEditingController(text: _n(_limits[i]).replaceAll('₹', ''));
    String? error;
    final title = _cost
        ? (band == 4
            ? 'Great is up to'
            : '${MileageBands.names[band]} is above')
        : (band == 4
            ? 'Great starts at'
            : '${MileageBands.names[band]} ends at');
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
                prefixText: _cost ? '₹' : null,
                suffixText: _cost ? 'per km' : 'km/L',
                errorText: error),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final v = double.tryParse(controller.text.trim());
                if (v == null || v <= lo || v >= hi) {
                  setDialog(() => error = hi.isFinite
                      ? 'Between ${_n(lo)} and ${_n(hi)}'
                      : 'More than ${_n(lo)}');
                  return;
                }
                Navigator.pop(ctx, v);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (value != null) await _saveLimits(List.of(_limits)..[i] = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final b = Theme.of(context).brightness;
    final typeName = vehicleTypeLabel(_vehicle.type).toLowerCase();
    return Scaffold(
      appBar: AppBar(
          title: Text(_cost ? 'Cost per km ranges' : 'Mileage ranges')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text('For ${_vehicle.name}. Changes save as you make them.',
              style: TextStyle(color: colors.textSecondary, fontSize: 15)),
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: Row(
                      children: [
                        for (var i = 0; i < 5; i++)
                          Expanded(
                              child: Container(
                                  height: 14, color: bandColor(i, b))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Spacer(),
                      for (final l in _limits)
                        Expanded(
                          flex: 2,
                          child: Text(_n(l),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  color: colors.textSecondary, fontSize: 12)),
                        ),
                      const Spacer(),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (var i = 0; i < 5; i++) ...[
                  if (i > 0)
                    Divider(
                        height: 1,
                        indent: 16,
                        endIndent: 16,
                        color: colors.cardBorder),
                  ListTile(
                    leading: CircleAvatar(
                        radius: 7, backgroundColor: bandColor(i, b)),
                    title: Text(MileageBands.names[i],
                        style: TextStyle(color: colors.textPrimary)),
                    trailing: Text('${_range(i)} ›',
                        style: TextStyle(color: colors.textSecondary)),
                    onTap: () => _edit(i),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text(
              _cost
                  ? 'Cost per km is the price per litre divided by km/L. A '
                      "fill-up's grade is the lower of its mileage and cost "
                      'grades.'
                  : 'Tap a band to change its limit. A fill-up\'s grade is the '
                      'lower of its mileage and cost grades.',
              style: TextStyle(color: colors.textSecondary, fontSize: 13)),
          if (_hasGauge) ...[
            const SizedBox(height: 16),
            _gaugeCard(colors),
          ],
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: _reset,
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
            child: Text('Reset to $typeName defaults'),
          ),
        ],
      ),
    );
  }
}
