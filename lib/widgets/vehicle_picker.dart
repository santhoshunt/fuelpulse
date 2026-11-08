import 'package:flutter/material.dart';
import '../screens/vehicle_edit_screen.dart';
import '../utils/page_routes.dart';
import '../theme/app_colors.dart';
import '../db/database_helper.dart';
import '../models/vehicle.dart';
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
          leading: Icon(vehicleIcon(v.type), color: AppColors.of(context).textSecondary, size: 22),
        ),
    ],
    selected: selectedId,
    actionLabel: 'Add vehicle',
  );
  if (result == null || !context.mounted) return null;
  if (result is PickerPicked<String>) {
    return vehicles.firstWhere((v) => v.id == result.value);
  }
  final created = await showVehicleEditor(context,
      nextSortOrder: vehicles.length);
  if (created == null) return null;
  await DatabaseHelper().insertVehicle(created);
  return created;
}

/// Opens [VehicleEditScreen] to add ([initial] null) or edit a vehicle.
/// Returns the vehicle to save, or null on back. Saving is the caller's.
Future<Vehicle?> showVehicleEditor(
  BuildContext context, {
  Vehicle? initial,
  int nextSortOrder = 0,
  Future<bool> Function()? onDelete,
}) =>
    Navigator.push<Vehicle>(
      context,
      SmoothPageRoute(
        page: VehicleEditScreen(
            initial: initial, nextSortOrder: nextSortOrder, onDelete: onDelete),
      ),
    );