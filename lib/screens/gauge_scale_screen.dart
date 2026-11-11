import 'package:flutter/material.dart';

import '../db/database_helper.dart';
import '../models/vehicle.dart';
import '../theme/app_colors.dart';
import '../utils/efficiency_calculator.dart';
import '../utils/gauge_scale.dart';
import '../widgets/gauge_card.dart' show GaugeCard;
import '../widgets/period_selector.dart' show SlidingSegments;

/// The Dashboard gauge's scale for one vehicle: Auto, fitted to the
/// fill-ups, or your own From and To. Saves each change as it is made.
class GaugeScaleScreen extends StatefulWidget {
  final Vehicle vehicle;

  const GaugeScaleScreen({super.key, required this.vehicle});

  @override
  State<GaugeScaleScreen> createState() => _GaugeScaleScreenState();
}

class _GaugeScaleScreenState extends State<GaugeScaleScreen> {
  /// The scale Auto gives today, and the custom one (null is Auto).
  (double, double)? _auto;
  (double, double)? _custom;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final id = widget.vehicle.id;
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

  Future<void> _save((double, double)? scale) async {
    setState(() => _custom = scale);
    await saveGaugeScale(widget.vehicle.id, scale);
  }

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  /// Asks for the gauge's From or To in km/L.
  Future<void> _edit({required bool from}) async {
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
            decoration: InputDecoration(suffixText: 'km/L', errorText: error),
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
    if (value != null) await _save(from ? (value, hi) : (lo, value));
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final muted = TextStyle(color: colors.textSecondary, fontSize: 13);
    final shown = _custom ?? _auto;
    Widget end(String label, double? v, bool from) => ListTile(
          contentPadding: EdgeInsets.zero,
          enabled: _custom != null,
          title: Text(label, style: TextStyle(color: colors.textPrimary)),
          trailing: Text(v == null ? '' : '${_n(v)} km/L ›', style: muted),
          onTap: () => _edit(from: from),
        );
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard gauge scale')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text(
              'For ${widget.vehicle.name}. The km/L range the Dashboard gauge '
              'shows. Changes save as you make them.',
              style: TextStyle(color: colors.textSecondary, fontSize: 15)),
          const SizedBox(height: 16),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SlidingSegments(
                    labels: const ['Auto', 'Custom'],
                    selected: _custom == null ? 0 : 1,
                    onTap: (i) =>
                        _save(i == 0 ? null : (_auto ?? (0.0, 25.0))),
                    background: Color.alphaBlend(
                        colors.textPrimary.withValues(alpha: 0.07),
                        colors.page),
                    height: 38,
                  ),
                  const SizedBox(height: 8),
                  if (_custom == null)
                    Text(
                        _auto == null
                            ? 'Fits the scale to your fill-ups.'
                            : 'Now ${_n(_auto!.$1)} to ${_n(_auto!.$2)} km/L, '
                                'fitted to your average and your best and '
                                'worst fill-ups.',
                        style: muted),
                  end('From', shown?.$1, true),
                  end('To', shown?.$2, false),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
