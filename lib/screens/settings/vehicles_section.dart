import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../db/database_helper.dart';
import '../../models/vehicle.dart';
import '../../services/service_reminders.dart';
import '../../widgets/vehicle_icon.dart';
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
    final v = await showVehicleEditor(context, nextSortOrder: _vehicles.length);
    if (v == null) return;
    await _db.insertVehicle(v);
    await _load();
  }

  Future<void> _edit(Vehicle vehicle) async {
    final v = await showVehicleEditor(context,
        initial: vehicle,
        onDelete: _vehicles.length > 1 ? () => _delete(vehicle) : null);
    if (v == null) return;
    await _db.updateVehicle(v);
    await _load();
  }

  /// Says whether the vehicle was deleted.
  Future<bool> _delete(Vehicle vehicle) async {
    final count = await _db.getLogCountFor(vehicle.id);
    if (!mounted) return false;
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
    if (confirm != true) return false;
    await _db.deleteVehicle(vehicle.id);
    await ServiceReminders.instance.rescheduleAll();
    if (mounted) showSettingsSnack(context, 'Deleted "${vehicle.name}".');
    await _load();
    return true;
  }

  String _subtitle(Vehicle v) {
    final cap = v.tankCapacity;
    final tank = cap == null
        ? 'Tank size not set'
        : '${cap.toStringAsFixed(cap % 1 == 0 ? 0 : 1)} L tank';
    return '${v.model.isEmpty ? vehicleTypeLabel(v.type) : v.model} · $tank';
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

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
        Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < _vehicles.length; i++) ...[
                if (i > 0)
                  Divider(
                      height: 1,
                      indent: 58,
                      endIndent: 16,
                      color: AppColors.of(context).cardBorder),
                // Tap opens the vehicle page, which has Delete.
                InkWell(
                  onTap: () => _edit(_vehicles[i]),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                    child: Row(
                      children: [
                        VehicleIcon.of(_vehicles[i], size: 30),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _vehicles[i].name,
                                style: TextStyle(
                                    color: AppColors.of(context).textPrimary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                _subtitle(_vehicles[i]),
                                style: TextStyle(
                                    color: AppColors.of(context).textSecondary,
                                    fontSize: 12),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right,
                            color: AppColors.of(context).textSecondary),
                      ],
                    ),
                  ),
                ),              ],
              Divider(height: 1, color: AppColors.of(context).cardBorder),
              // A full-width row, so its press highlight stays inside it.
              InkWell(
                onTap: _add,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.add, size: 18, color: accent),
                      const SizedBox(width: 8),
                      Text('Add vehicle',
                          style: TextStyle(
                              color: accent,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),      ],
    );
  }
}
