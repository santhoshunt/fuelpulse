import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'models/theme_preference.dart';
import 'screens/home_screen.dart';
import 'utils/theme_manager.dart' as tm;

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize FFI for desktop platforms (Linux, Windows, macOS).
  // Use NoIsolate variant so the library override stays in-process.
  if (!kIsWeb && (Platform.isLinux || Platform.isWindows || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
  }

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF080808),
  ));
  runApp(const FuelPulseApp());
}

class FuelPulseApp extends StatefulWidget {
  const FuelPulseApp({super.key});

  @override
  State<FuelPulseApp> createState() => _FuelPulseAppState();
}

class _FuelPulseAppState extends State<FuelPulseApp> {
  ThemePreference _theme = ThemePreference.defaults;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final theme = await tm.loadTheme();
    setState(() {
      _theme = theme;
      _loaded = true;
    });
  }

  void _onThemeChanged(ThemePreference theme) {
    setState(() => _theme = theme);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: tm.buildThemeData(ThemePreference.defaults),
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return MaterialApp(
      title: 'FuelPulse',
      debugShowCheckedModeBanner: false,
      theme: tm.buildThemeData(_theme),
      home: HomeScreen(
        theme: _theme,
        onThemeChanged: _onThemeChanged,
      ),
    );
  }
}
