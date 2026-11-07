import 'package:flutter/material.dart';

/// The Dashboard tab. Filled in by the gauge step.
class DashboardScreen extends StatelessWidget {
  final ValueNotifier<int> reload;

  const DashboardScreen({super.key, required this.reload});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Dashboard')),
      body: const SizedBox.shrink(),
    );
  }
}
