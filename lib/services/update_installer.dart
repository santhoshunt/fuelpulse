import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

// Ported from the expense tracker's updater. FuelPulse adds two reads to
// the channel: the installed version (instead of package_info_plus) and the
// phone's primary architecture (to pick the matching split APK).

/// Hands a downloaded update to Android. The native side (UpdateInstaller.kt)
/// installs a file only if it is this app, signed with this app's key, and
/// newer than the installed build; it accepts nothing but a file name in the
/// app's own `cache/updates` folder.
abstract class UpdateInstaller {
  /// Whether Android lets this app install updates ("Install unknown apps").
  Future<bool> canInstall();

  /// Opens the system page where that is switched on or off.
  Future<void> openInstallSettings();

  /// Verifies [apk] and starts the install. Completes with null once the
  /// install is under way (the app is then replaced and restarts), or with
  /// the reason it was refused or failed.
  Future<String?> install(File apk);

  /// The installed versionName, e.g. "2.0.0".
  Future<String> currentVersion();

  /// The first of the phone's ABIs that FuelPulse publishes an APK for, or
  /// null when it runs none of them.
  Future<String?> primaryAbi();
}

/// The Android implementation over the `fuelpulse/update` channel.
class ChannelUpdateInstaller implements UpdateInstaller {
  static const _channel = MethodChannel('fuelpulse/update');

  ChannelUpdateInstaller._() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'installFailed') {
        final pending = _pending;
        _pending = null;
        if (pending != null && !pending.isCompleted) {
          pending.complete(call.arguments as String? ?? 'Install failed.');
        }
      }
    });
  }

  static final ChannelUpdateInstaller instance = ChannelUpdateInstaller._();

  /// The running install: a failure reported by the system after the commit
  /// arrives through [_channel] and completes it.
  Completer<String?>? _pending;

  @override
  Future<bool> canInstall() async {
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<void> openInstallSettings() async {
    try {
      await _channel.invokeMethod<bool>('openInstallSettings');
    } on PlatformException {
      // Nothing to open on this ROM; the sheet still explains the setting.
    } on MissingPluginException {
      // Not Android.
    }
  }

  @override
  Future<String> currentVersion() async {
    final v = await _channel.invokeMethod<String>('currentVersion');
    if (v == null || v.isEmpty) throw StateError('No version from Android');
    return v;
  }

  @override
  Future<String?> primaryAbi() =>
      _channel.invokeMethod<String>('primaryAbi');

  @override
  Future<String?> install(File apk) async {
    final name = apk.uri.pathSegments.last;
    final pending = _pending = Completer<String?>();
    try {
      await _channel.invokeMethod<void>('install', {'fileName': name});
    } on PlatformException catch (e) {
      _pending = null;
      return e.message ?? 'Install failed.';
    } on MissingPluginException {
      _pending = null;
      return 'Updates install only on Android.';
    }
    // Started: success replaces the app (this never completes); a refusal
    // from the system comes back as installFailed. A confirm screen the
    // user leaves open also never completes, so the sheet stops waiting.
    return pending.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () {
        // Nobody waits any more; a later installFailed must not complete
        // this one.
        if (identical(_pending, pending)) _pending = null;
        return null;
      },
    );
  }
}
