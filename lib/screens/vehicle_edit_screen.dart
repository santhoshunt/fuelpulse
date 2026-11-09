import 'package:flutter/material.dart';

import '../models/vehicle.dart';
import '../theme/app_colors.dart';
import '../utils/custom_pictures.dart';
import '../widgets/vehicle_icon.dart';
import '../widgets/vehicle_picker.dart' show vehicleIcon, vehicleTypeLabel;
import 'part_form_screen.dart';
import 'settings/settings_widgets.dart';

/// Add ([initial] null) or edit a vehicle: name, make and model, type and
/// tank size, monthly fuel budget, and (edit only) its tyres and battery.
/// Its grading ranges are under Settings → Grading. Save returns the
/// vehicle; saving it is the caller's. Tyres and battery save on their own. [onDelete] (edit only) deletes after its own confirmation and
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
  late final _budget = TextEditingController(
      text: widget.initial?.monthlyBudget?.toStringAsFixed(0) ?? '');
  late VehicleType _type = widget.initial?.type ?? VehicleType.car;

  /// A picture name, `file:NAME` for your own, or null for the default.
  late String? _icon = widget.initial?.icon;

  String? _nameError;
  String? _capError;
  String? _budgetError;

  @override
  void dispose() {
    _name.dispose();
    _model.dispose();
    _cap.dispose();
    _budget.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    final capText = _cap.text.trim();
    final cap = capText.isEmpty ? null : double.tryParse(capText);
    final budgetText = _budget.text.trim();
    final budget = budgetText.isEmpty ? null : double.tryParse(budgetText);
    setState(() {
      _nameError = name.isEmpty ? 'Enter a name' : null;
      _capError = capText.isNotEmpty && (cap == null || cap < 0)
          ? 'Enter litres, or leave empty'
          : null;
      _budgetError = budgetText.isNotEmpty && (budget == null || budget < 0)
          ? 'Enter rupees, or leave empty'
          : null;
    });
    if (_nameError != null || _capError != null || _budgetError != null) {
      return;
    }
    final perMonth = budget != null && budget > 0 ? budget : null;
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
              icon: _icon,
              tankCapacity: tank,
              monthlyBudget: perMonth,
              sortOrder: widget.nextSortOrder,
              createdAt: DateTime.now().toIso8601String(),
            )
          : initial.copyWith(
              name: name,
              type: _type,
              model: _model.text.trim(),
              icon: _icon,
              clearIcon: _icon == null,
              tankCapacity: tank,
              clearTankCapacity: tank == null,
              monthlyBudget: perMonth,
              clearMonthlyBudget: perMonth == null,
            ),
    );
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
                  onSelected: (_) => setState(() {
                    _type = t;
                    // A picture of another type no longer fits.
                    if (_icon != null &&
                        !_icon!.startsWith('file:') &&
                        !picturesFor(t).contains(_icon)) {
                      _icon = null;
                    }
                  }),
                ),
            ],
          ),
          const SizedBox(height: 24),
          sectionHeader('Picture'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final p in picturesFor(_type))
                ChoiceChip(
                  avatar: VehicleIcon(type: _type, icon: p, size: 22),
                  label: Text(kVehiclePictures[p]!),
                  selected: (_icon ?? picturesFor(_type).first) == p,
                  onSelected: (_) => setState(() => _icon = p),
                ),
              ChoiceChip(
                avatar: _icon != null && _icon!.startsWith('file:')
                    ? VehicleIcon(type: _type, icon: _icon, size: 22)
                    : const Icon(Icons.add_photo_alternate_outlined, size: 18),
                label: const Text('Your picture'),
                selected: _icon?.startsWith('file:') ?? false,
                onSelected: (_) async {
                  final name = await pickSquarePicture('vehicle');
                  if (name != null && mounted) {
                    setState(() => _icon = 'file:$name');
                  }
                },
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
          sectionHeader('Budget'),
          const SizedBox(height: 12),
          TextField(
            controller: _budget,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Monthly fuel budget (optional)',
              prefixText: '₹ ',
              errorText: _budgetError,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 4),
            child: Text('Shows how much is left this month on the Dashboard.',
                style: note),
          ),
          if (widget.initial != null) ...[
            const SizedBox(height: 24),
            sectionHeader('Tyres and battery'),
            const SizedBox(height: 12),
            PartsSection(vehicleId: widget.initial!.id),
          ],
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
