import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import '../models/vehicle.dart';
import 'constants.dart';

// The active vehicle is stored by id under kActiveVehicleKey; the vehicles
// themselves live in the database.

/// The stored active vehicle when it still exists, else the first by sort
/// order (a restore or delete may have removed the stored one).
Future<Vehicle> loadActiveVehicle() async {
  final db = DatabaseHelper();
  final prefs = await SharedPreferences.getInstance();
  final id = prefs.getString(kActiveVehicleKey);
  if (id != null) {
    final v = await db.getVehicle(id);
    if (v != null) return v;
  }
  var vehicles = await db.getVehicles();
  if (vehicles.isEmpty) {
    await db.ensureDefaultVehicle();
    vehicles = await db.getVehicles();
  }
  return vehicles.first;
}

Future<void> setActiveVehicle(String id) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kActiveVehicleKey, id);
}

/// Before v2.0.0 tank capacity was one global preference. Moves it onto the
/// default vehicle once, unless that vehicle already has a capacity, then
/// removes the preference. Kept out of the SQL migration so the schema
/// upgrade stays testable on SQL alone.
Future<void> migrateLegacyTankCapacity() async {
  final prefs = await SharedPreferences.getInstance();
  final cap = prefs.getDouble(kTankCapacityKey);
  if (cap == null) return;
  final db = DatabaseHelper();
  final v = await db.getVehicle(kDefaultVehicleId);
  if (v != null && v.tankCapacity == null && cap > 0) {
    await db.updateVehicle(v.copyWith(tankCapacity: cap));
  }
  await prefs.remove(kTankCapacityKey);
}
