import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../db/database_helper.dart';
import '../../models/vehicle.dart';
import '../../widgets/vehicle_picker.dart';
import 'settings_widgets.dart';

/// Every vehicle with its tank size: add, edit and delete. Replaces the
/// single global Tank Capacity setting from before v2.0.0.
class VehiclesSection extends StatefulWidget {
  const VehiclesSection({super.key});

  @override
  State<VehiclesSection> createState() => _VehiclesSectionState();
}

class _VehiclesSectionState extends State<VehiclesSection> {
  final _db = DatabaseHelper();
  List<Vehicle> _vehicles = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final vehicles = await _db.getVehicles();
    if (mounted) setState(() => _vehicles = vehicles);
  }

  Future<void> _add() async {
    final v = await showVehicleDialog(context, nextSortOrder: _vehicles.length);
    if (v == null) return;
    await _db.insertVehicle(v);
    await _load();
  }

  Future<void> _edit(Vehicle vehicle) async {
    final v = await showVehicleDialog(context, initial: vehicle);
    if (v == null) return;
    await _db.updateVehicle(v);
    await _load();
  }

  Future<void> _delete(Vehicle vehicle) async {
    final count = await _db.getLogCountFor(vehicle.id);
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${vehicle.name}"?'),
        content: Text(count == 0
            ? 'This vehicle has no fill-ups.'
            : 'This also deletes its $count '
                '${count == 1 ? 'fill-up' : 'fill-ups'}. '
                'This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.of(context).danger, foregroundColor: Colors.white),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm != true) return;
    await _db.deleteVehicle(vehicle.id);
    if (mounted) showSettingsSnack(context, 'Deleted "${vehicle.name}".');
    await _load();
  }

  String _subtitle(Vehicle v) {
    final cap = v.tankCapacity;
    final tank = cap == null
        ? 'Tank size not set'
        : '${cap.toStringAsFixed(cap % 1 == 0 ? 0 : 1)} L tank';
    return '${vehicleTypeLabel(v.type)} · $tank';
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    final canDelete = _vehicles.length > 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sectionHeader('Vehicles'),
        const SizedBox(height: 4),
        Text(
          'Each vehicle has its own fill-ups, stats and tank size. Switch '
          'between them from the vehicle name on the Dashboard or Fuel tab.',
          style: TextStyle(color: AppColors.of(context).textSecondary, fontSize: 12),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: AppColors.of(context).card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.of(context).cardBorder),
          ),
          child: Column(
            children: [
              for (var i = 0; i < _vehicles.length; i++) ...[
                if (i > 0)
                  Divider(
                      height: 1, color: AppColors.of(context).cardBorder),
                Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Row(
                    children: [
                      Icon(vehicleIcon(_vehicles[i].type),
                          color: AppColors.of(context).textSecondary, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _vehicles[i].name,
                              style: TextStyle(
                                  color: AppColors.of(context).textPrimary, fontSize: 14),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              _subtitle(_vehicles[i]),
                              style: TextStyle(
                                  color: AppColors.of(context).textSecondary, fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Edit vehicle',
                        icon: Icon(Icons.edit_outlined,
                            size: 18, color: accent.withValues(alpha: 0.7)),
                        onPressed: () => _edit(_vehicles[i]),
                        visualDensity: VisualDensity.compact,
                      ),
                      // The last vehicle cannot go: every log needs one.
                      IconButton(
                        tooltip: canDelete
                            ? 'Delete vehicle'
                            : 'Add another vehicle before deleting this one',
                        icon: Icon(Icons.delete_outline,
                            size: 18,
                            color: canDelete
                                ? AppColors.of(context).danger.withValues(alpha: 0.7)
                                : AppColors.of(context).textSecondary.withValues(alpha: 0.4)),
                        onPressed:
                            canDelete ? () => _delete(_vehicles[i]) : null,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              ],
              Divider(height: 1, color: AppColors.of(context).cardBorder),
              TextButton.icon(
                onPressed: _add,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add vehicle'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
