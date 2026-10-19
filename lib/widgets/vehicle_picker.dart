import 'package:flutter/material.dart';
import '../db/database_helper.dart';
import '../models/vehicle.dart';
import '../utils/constants.dart';
import 'option_picker.dart';

IconData vehicleIcon(VehicleType type) => switch (type) {
      VehicleType.car => Icons.directions_car_outlined,
      VehicleType.bike => Icons.two_wheeler,
      VehicleType.other => Icons.local_shipping_outlined,
    };

String vehicleTypeLabel(VehicleType type) => switch (type) {
      VehicleType.car => 'Car',
      VehicleType.bike => 'Bike',
      VehicleType.other => 'Other',
    };

/// Bottom sheet listing [vehicles] with an "Add vehicle" footer. Returns the
/// vehicle to switch to (a newly added one is saved first), or null when
/// dismissed.
Future<Vehicle?> showVehiclePicker(
  BuildContext context, {
  required List<Vehicle> vehicles,
  required String selectedId,
}) async {
  final result = await showOptionPicker<String>(
    context: context,
    title: 'Vehicle',
    options: [
      for (final v in vehicles)
        PickerOption(
          value: v.id,
          label: v.name,
          leading: Icon(vehicleIcon(v.type), color: kTextSecondary, size: 22),
        ),
    ],
    selected: selectedId,
    actionLabel: 'Add vehicle',
  );
  if (result == null || !context.mounted) return null;
  if (result is PickerPicked<String>) {
    return vehicles.firstWhere((v) => v.id == result.value);
  }
  final created = await showVehicleDialog(context,
      nextSortOrder: vehicles.length);
  if (created == null) return null;
  await DatabaseHelper().insertVehicle(created);
  return created;
}

/// Add ([initial] null) or edit a vehicle: name, type and tank size.
/// Returns the vehicle to save, or null on cancel. Saving is the caller's.
Future<Vehicle?> showVehicleDialog(
  BuildContext context, {
  Vehicle? initial,
  int nextSortOrder = 0,
}) {
  final nameController = TextEditingController(text: initial?.name ?? '');
  final capController = TextEditingController(
      text: initial?.tankCapacity != null
          ? initial!.tankCapacity!.toString()
          : '');
  var type = initial?.type ?? VehicleType.car;
  String? nameError;
  String? capError;

  return showDialog<Vehicle>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        void save() {
          final name = nameController.text.trim();
          final capText = capController.text.trim();
          final cap = capText.isEmpty ? null : double.tryParse(capText);
          setDialogState(() {
            nameError = name.isEmpty ? 'Enter a name' : null;
            capError = capText.isNotEmpty && (cap == null || cap < 0)
                ? 'Enter litres, or leave empty'
                : null;
          });
          if (nameError != null || capError != null) return;
          final tank = cap != null && cap > 0 ? cap : null;
          Navigator.pop(
            ctx,
            initial == null
                ? Vehicle(
                    id: Vehicle.generateId(),
                    name: name,
                    type: type,
                    tankCapacity: tank,
                    sortOrder: nextSortOrder,
                    createdAt: DateTime.now().toIso8601String(),
                  )
                : initial.copyWith(
                    name: name,
                    type: type,
                    tankCapacity: tank,
                    clearTankCapacity: tank == null,
                  ),
          );
        }

        return AlertDialog(
          title: Text(initial == null ? 'Add Vehicle' : 'Edit Vehicle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: initial == null,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Name',
                    hintText: 'e.g. Swift',
                    errorText: nameError,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final t in VehicleType.values)
                      ChoiceChip(
                        avatar: Icon(vehicleIcon(t), size: 18),
                        label: Text(vehicleTypeLabel(t)),
                        selected: type == t,
                        onSelected: (_) => setDialogState(() => type = t),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: capController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Tank size (optional)',
                    suffixText: 'L',
                    helperText: 'Used to estimate fuel left in the tank',
                    errorText: capError,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            ElevatedButton(onPressed: save, child: const Text('Save')),
          ],
        );
      },
    ),
  );
}
