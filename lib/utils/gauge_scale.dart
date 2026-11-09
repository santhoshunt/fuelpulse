import 'package:shared_preferences/shared_preferences.dart';

/// The Dashboard gauge's scale for one vehicle. Auto, the default, fits the
/// scale to the fill-ups (GaugeCard.scaleFor); Custom keeps a From and To.
String _key(String vehicleId) => 'fuel_gauge_scale_$vehicleId';

/// The custom From and To in km/L, or null for Auto.
Future<(double, double)?> loadGaugeScale(String vehicleId) async {
  final raw = (await SharedPreferences.getInstance()).getString(_key(vehicleId));
  final parts = raw?.split('|');
  final lo = double.tryParse(parts?.first ?? '');
  final hi = double.tryParse(parts?.last ?? '');
  return lo != null && hi != null && hi > lo ? (lo, hi) : null;
}

/// Saves a custom From and To, or Auto when [scale] is null.
Future<void> saveGaugeScale(String vehicleId, (double, double)? scale) async {
  final prefs = await SharedPreferences.getInstance();
  if (scale == null) {
    await prefs.remove(_key(vehicleId));
  } else {
    await prefs.setString(_key(vehicleId), '${scale.$1}|${scale.$2}');
  }
}
