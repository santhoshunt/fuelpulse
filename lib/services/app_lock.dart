import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';

/// App lock: the app asks for the fingerprint, face or phone PIN when it
/// opens, and again after being away longer than the chosen time.
const kAppLockKey = 'fuel_app_lock';

/// Seconds away before it locks again: 0, 60 or 300.
const kAppLockAfterKey = 'fuel_app_lock_after';
const kAppLockAfterDefault = 60;

bool get appLockSupported => !kIsWeb && Platform.isAndroid;

int _pickersOpen = 0;
bool _skipNextLock = false;

/// Runs [pick], a camera, gallery or file picker, so that coming back from
/// it does not lock the app. The app pauses while the picker is open; that
/// pause is marked at the time, because the picker's result and the resume
/// can reach Dart in either order.
Future<T> withoutRelock<T>(Future<T> Function() pick) async {
  _pickersOpen++;
  try {
    return await pick();
  } finally {
    _pickersOpen--;
  }
}

Future<bool> appLockEnabled() async {
  if (!appLockSupported) return false;
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(kAppLockKey) ?? false;
}

/// Shows Android's unlock prompt. True when the person unlocked.
Future<bool> authenticate(String reason) async {
  try {
    return await LocalAuthentication()
        .authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
  } catch (e) {
    debugPrint('Unlock failed: $e');
    return false;
  }
}

/// Whether the phone has a screen lock the prompt can use.
Future<bool> canLock() async {
  try {
    return await LocalAuthentication().isDeviceSupported();
  } catch (_) {
    return false;
  }
}

/// Covers the app with a lock screen while locked. Locks on open when app
/// lock is on, and on coming back after the chosen time away.
class AppLockGate extends StatefulWidget {
  final bool initiallyLocked;
  final Widget child;

  const AppLockGate(
      {super.key, required this.initiallyLocked, required this.child});

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  late bool _locked = widget.initiallyLocked;
  bool _asking = false;
  DateTime? _leftAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_locked) WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) async {
    // The unlock prompt itself sends the app to the background; ignore it.
    if (_asking) return;
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      _leftAt ??= DateTime.now();
      if (_pickersOpen > 0) _skipNextLock = true;
    } else if (state == AppLifecycleState.resumed) {
      final left = _leftAt;
      _leftAt = null;
      if (_skipNextLock) {
        _skipNextLock = false;
        return;
      }
      if (left == null || _locked || !await appLockEnabled()) return;
      final prefs = await SharedPreferences.getInstance();
      final after = prefs.getInt(kAppLockAfterKey) ?? kAppLockAfterDefault;
      if (DateTime.now().difference(left).inSeconds >= after && mounted) {
        setState(() => _locked = true);
        await _unlock();
      }
    }
  }

  Future<void> _unlock() async {
    if (_asking) return;
    _asking = true;
    final ok = await authenticate("Unlock My H'ness");
    _asking = false;
    if (ok && mounted) setState(() => _locked = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (_locked) _LockScreen(onUnlock: _unlock),
      ],
    );
  }
}

class _LockScreen extends StatelessWidget {
  final VoidCallback onUnlock;

  const _LockScreen({required this.onUnlock});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    const light = Color(0xFFDCE6F5);
    return Positioned.fill(
      child: Material(
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.gaugeStart, colors.gaugeEnd],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 56, color: Colors.white),
                  const SizedBox(height: 16),
                  const Text("My H'ness is locked",
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  const Text('Use your fingerprint, face or phone PIN',
                      style: TextStyle(color: light, fontSize: 14)),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: onUnlock,
                    icon: const Icon(Icons.fingerprint),
                    label: const Text('Unlock'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
