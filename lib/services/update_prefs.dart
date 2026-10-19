import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';

// The updater's stored state. The expense tracker keeps these in its
// SettingsProvider; FuelPulse has no provider, so plain SharedPreferences
// under the keys in constants.dart.

/// Whether Home checks GitHub once a day. On unless switched off.
Future<bool> updateOnLaunch() async =>
    (await SharedPreferences.getInstance()).getBool(kUpdateOnLaunchKey) ??
    true;

Future<void> setUpdateOnLaunch(bool value) async =>
    (await SharedPreferences.getInstance()).setBool(kUpdateOnLaunchKey, value);

Future<DateTime?> updateLastCheck() async {
  final ms = (await SharedPreferences.getInstance()).getInt(kUpdateLastCheckKey);
  return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
}

Future<void> markUpdateChecked(DateTime when) async =>
    (await SharedPreferences.getInstance())
        .setInt(kUpdateLastCheckKey, when.millisecondsSinceEpoch);

/// The newest tag the user answered with "Not now"; the banner stays hidden
/// until a newer one appears.
Future<String?> dismissedUpdateTag() async =>
    (await SharedPreferences.getInstance()).getString(kUpdateDismissedKey);

Future<void> dismissUpdate(String tag) async =>
    (await SharedPreferences.getInstance()).setString(kUpdateDismissedKey, tag);

/// The tag an install was started for, so the next launch can say whether
/// it worked. Null clears it.
Future<String?> installingUpdateTag() async =>
    (await SharedPreferences.getInstance()).getString(kUpdateInstallingKey);

Future<void> setInstallingUpdateTag(String? tag) async {
  final prefs = await SharedPreferences.getInstance();
  if (tag == null) {
    await prefs.remove(kUpdateInstallingKey);
  } else {
    await prefs.setString(kUpdateInstallingKey, tag);
  }
}
