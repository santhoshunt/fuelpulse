import 'package:flutter/material.dart';

import '../models/vehicle.dart';
import '../theme/app_colors.dart';
import '../utils/mileage_bands.dart';
import '../widgets/vehicle_picker.dart' show vehicleTypeLabel;

/// The five km/L bands for one vehicle: a preview bar, one row per band,
/// and a reset to the type's defaults. Done returns the four limits.
class MileageRangesScreen extends StatefulWidget {
  final String vehicleName;
  final VehicleType type;
  final List<double> limits;

  const MileageRangesScreen({
    super.key,
    required this.vehicleName,
    required this.type,
    required this.limits,
  });

  @override
  State<MileageRangesScreen> createState() => _MileageRangesScreenState();
}

class _MileageRangesScreenState extends State<MileageRangesScreen> {
  late List<double> _limits = List.of(widget.limits);

  static String _n(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

  String _range(int band) => switch (band) {
        0 => 'below ${_n(_limits[0])} km/L',
        4 => '${_n(_limits[3])} and above',
        _ => '${_n(_limits[band - 1])} to ${_n(_limits[band])}',
      };

  /// Each band edits the limit it ends at; Great edits where it starts.
  Future<void> _edit(int band) async {
    final i = band.clamp(0, 3);
    final lo = i == 0 ? 0.0 : _limits[i - 1];
    final hi = i == 3 ? double.infinity : _limits[i + 1];
    final controller = TextEditingController(text: _n(_limits[i]));
    String? error;
    final value = await showDialog<double>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: Text(band == 4
              ? 'Great starts at'
              : '${MileageBands.names[band]} ends at'),
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
    if (value != null) setState(() => _limits[i] = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final b = Theme.of(context).brightness;
    final typeName = vehicleTypeLabel(widget.type).toLowerCase();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mileage ranges'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _limits),
            child: const Text('Done'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text('For ${widget.vehicleName}',
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
              'Tap a band to change its limit. These colours mark km/L on '
              'the Fuel list and the refill page.',
              style: TextStyle(color: colors.textSecondary, fontSize: 13)),
          const SizedBox(height: 20),
          OutlinedButton(
            onPressed: () => setState(
                () => _limits = List.of(defaultBandsFor(widget.type).limits)),
            style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48)),
            child: Text('Reset to $typeName defaults'),
          ),
        ],
      ),
    );
  }
}
