import 'package:flutter/material.dart';

import '../models/vehicle.dart';
import '../theme/app_colors.dart';
import '../utils/mileage_bands.dart';
import '../utils/page_routes.dart';
import '../widgets/vehicle_picker.dart' show vehicleIcon, vehicleTypeLabel;
import 'mileage_ranges_screen.dart';
import 'settings/settings_widgets.dart';

/// Add ([initial] null) or edit a vehicle: name, make and model, type, tank
/// size and mileage ranges. Save returns the vehicle; saving it is the
/// caller's. [onDelete] (edit only) deletes after its own confirmation and
/// says whether it did.
class VehicleEditScreen extends StatefulWidget {
  final Vehicle? initial;
  final int nextSortOrder;
  final Future<bool> Function()? onDelete;

  const VehicleEditScreen({
    super.key,
    this.initial,
    this.nextSortOrder = 0,
    this.onDelete,
  });

  @override
  State<VehicleEditScreen> createState() => _VehicleEditScreenState();
}

class _VehicleEditScreenState extends State<VehicleEditScreen> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final _model =
      TextEditingController(text: widget.initial?.model ?? '');
  late final _cap = TextEditingController(
      text: widget.initial?.tankCapacity?.toString() ?? '');
  late VehicleType _type = widget.initial?.type ?? VehicleType.car;

  /// Null keeps following the type's defaults.
  late List<double>? _bands = widget.initial?.mileageBands;
  String? _nameError;
  String? _capError;

  @override
  void dispose() {
    _name.dispose();
    _model.dispose();
    _cap.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final capText = _cap.text.trim();
    final cap = capText.isEmpty ? null : double.tryParse(capText);
    setState(() {
      _nameError = name.isEmpty ? 'Enter a name' : null;
      _capError = capText.isNotEmpty && (cap == null || cap < 0)
          ? 'Enter litres, or leave empty'
          : null;
    });
    if (_nameError != null || _capError != null) return;
    final tank = cap != null && cap > 0 ? cap : null;
    final initial = widget.initial;
    Navigator.pop(
      context,
      initial == null
          ? Vehicle(
              id: Vehicle.generateId(),
              name: name,
              type: _type,
              model: _model.text.trim(),
              mileageBands: _bands,
              tankCapacity: tank,
              sortOrder: widget.nextSortOrder,
              createdAt: DateTime.now().toIso8601String(),
            )
          : initial.copyWith(
              name: name,
              type: _type,
              model: _model.text.trim(),
              mileageBands: _bands,
              clearMileageBands: _bands == null,
              tankCapacity: tank,
              clearTankCapacity: tank == null,
            ),
    );
  }

  Future<void> _ranges() async {
    final limits = await Navigator.push<List<double>>(
      context,
      SmoothPageRoute(
        page: MileageRangesScreen(
          vehicleName: _name.text.trim().isEmpty ? 'this vehicle' : _name.text.trim(),
          type: _type,
          limits: _bands ?? defaultBandsFor(_type).limits,
        ),
      ),
    );
    if (limits == null) return;
    final defaults = defaultBandsFor(_type).limits;
    setState(() {
      var same = true;
      for (var i = 0; i < 4; i++) {
        if (limits[i] != defaults[i]) same = false;
      }
      _bands = same ? null : limits;
    });
  }

  Future<void> _delete() async {
    if (await widget.onDelete!() && mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final note = TextStyle(color: colors.textSecondary, fontSize: 12);
    return Scaffold(
      appBar: AppBar(
          title: Text(widget.initial == null ? 'Add Vehicle' : 'Edit Vehicle')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          sectionHeader('Vehicle'),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            autofocus: widget.initial == null,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Name',
              hintText: 'e.g. Swift',
              errorText: _nameError,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _model,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Make and model (optional)',
              hintText: 'e.g. Royal Enfield Classic 350',
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final t in VehicleType.values)
                ChoiceChip(
                  avatar: Icon(vehicleIcon(t), size: 18),
                  label: Text(vehicleTypeLabel(t)),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _type = t),
                ),
            ],
          ),
          const SizedBox(height: 24),
          sectionHeader('Tank'),
          const SizedBox(height: 12),
          TextField(
            controller: _cap,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Tank size (optional)',
              suffixText: 'L',
              errorText: _capError,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text('Leave empty to hide the tank estimate.', style: note),
          ),
          const SizedBox(height: 24),
          sectionHeader('Mileage'),
          const SizedBox(height: 12),
          settingsGroup([
            SettingsRow(
              icon: Icons.tune,
              label: 'Mileage ranges',
              trailing: Text(
                  _bands == null
                      ? '${vehicleTypeLabel(_type)} defaults'
                      : 'Custom',
                  style: TextStyle(color: colors.textSecondary, fontSize: 15)),
              onTap: _ranges,
            ),
          ]),
          const SizedBox(height: 28),
          SizedBox(
            height: 52,
            child: ElevatedButton(onPressed: _save, child: const Text('Save')),
          ),
          if (widget.onDelete != null) ...[
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _delete,
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.danger,
                side: BorderSide(color: colors.danger.withValues(alpha: 0.35)),
                minimumSize: const Size.fromHeight(48),
              ),
              child: const Text('Delete vehicle'),
            ),
          ],
        ],
      ),
    );
  }
}
