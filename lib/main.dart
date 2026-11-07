import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'screens/app_shell.dart';
import 'theme/app_theme.dart';
import 'utils/appearance_prefs.dart';
import 'utils/vehicle_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize FFI for desktop platforms (Linux, Windows, macOS).
  // Use NoIsolate variant so the library override stays in-process.
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  }

  // One-time move of the pre-v2.0.0 global tank capacity onto the default
  // vehicle. A failure here must not stop the app from starting.
  try {
    await migrateLegacyTankCapacity();
  } catch (e) {
    debugPrint('Tank capacity migration failed: $e');
  }

  // Loaded before the first frame so the app never flashes the wrong theme.
  try {
    await reloadAppearance();
  } catch (e) {
    debugPrint('Appearance load failed: $e');
  }

  runApp(const FuelPulseApp());
}

class FuelPulseApp extends StatelessWidget {
  const FuelPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Appearance>(
      valueListenable: appearance,
      builder: (context, a, _) => MaterialApp(
        title: 'FuelPulse',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(a.palette, Brightness.light),
        darkTheme: buildAppTheme(a.palette, Brightness.dark),
        themeMode: a.mode,
        home: const AppShell(),
      ),
    );
  }
}
