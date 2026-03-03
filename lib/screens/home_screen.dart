import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database_helper.dart';
import '../models/fuel_log.dart';
import '../utils/constants.dart';
import '../utils/efficiency_calculator.dart';
import '../utils/page_routes.dart';
import '../utils/tank_level_calculator.dart';
import '../widgets/fuel_log_tile.dart';
import '../widgets/glossy_card.dart';
import 'add_entry_screen.dart';
import 'edit_entry_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import '../models/theme_preference.dart';

class HomeScreen extends StatefulWidget {
  final ThemePreference theme;
  final ValueChanged<ThemePreference> onThemeChanged;

  const HomeScreen({
    super.key,
    required this.theme,
    required this.onThemeChanged,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _db = DatabaseHelper();
  List<FuelLog> _logs = [];
  List<FuelLog> _chronoLogs = [];
  Map<String, EfficiencyResult> _efficiencyMap = {};
  Map<String, double> _tankLevels = {};
  double _tankCapacity = 0;
  double _overallAvg = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final logs = await _db.getAllLogs();
      final chrono = await _db.getAllLogsChrono();
      final prefs = await SharedPreferences.getInstance();
      final cap = prefs.getDouble(kTankCapacityKey) ?? 0;

      final effMap = calculateEfficiency(chrono);
      final levels = calculateTankLevels(chrono, cap, effMap);

      // Overall average efficiency
      double totalKm = 0, totalL = 0;
      int segStart = -1;
      for (int i = 0; i < chrono.length; i++) {
        if (chrono[i].fullTank) {
          if (segStart >= 0 && segStart != i) {
            totalKm += chrono[i].odometer - chrono[segStart].odometer;
            for (int j = segStart + 1; j <= i; j++) {
              totalL += chrono[j].liters;
            }
          }
          segStart = i;
        }
      }

      setState(() {
        _logs = logs;
        _chronoLogs = chrono;
        _efficiencyMap = effMap;
        _tankLevels = levels;
        _tankCapacity = cap;
        _overallAvg = totalL > 0 ? totalKm / totalL : 0;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error loading data: $e');
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _deleteLog(FuelLog log) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Entry'),
        content: Text(
            'Delete the fill-up on ${log.odometer} km? This cannot be undone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: kDanger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _db.deleteLog(log.id);
      _loadData();
    }
  }

  /// Distance this fill-up's fuel powered (to next entry).
  int? _distanceToNext(FuelLog log) {
    final idx = _chronoLogs.indexWhere((l) => l.id == log.id);
    if (idx < 0 || idx >= _chronoLogs.length - 1) return null;
    return _chronoLogs[idx + 1].odometer - log.odometer;
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      body: SafeArea(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          switchInCurve: Curves.easeOutCubic,
          child: _loading
              ? const Center(
                  key: ValueKey('loading'),
                  child: CircularProgressIndicator(),
                )
              : Column(
                  key: const ValueKey('content'),
                  children: [
                    _buildAppBar(accent),
                    if (_logs.isNotEmpty) _buildSummaryBanner(accent),
                    Expanded(
                      child:
                          _logs.isEmpty ? _buildEmptyState() : _buildList(),
                    ),
                  ],
                ),
        ),
      ),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton(
          onPressed: _goToAdd,
          child: const Icon(Icons.add, size: 28),
        ),
      ),
    );
  }

  Widget _buildAppBar(Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Row(
        children: [
          Builder(
            builder: (context) {
              return Text(
                'FuelPulse',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  foreground: Paint()
                    ..shader = ui.Gradient.linear(
                      const Offset(0, 0),
                      const Offset(150, 0),
                      [accent, accent.withValues(alpha: 0.6)],
                    ),
                ),
              );
            },
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: kTextSecondary),
            onPressed: _goToSettings,
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBanner(Color accent) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: GestureDetector(
      onTap: _goToStats,
      child: GlossyCard(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        borderRadius: 18,
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _overallAvg > 0
                      ? '${_overallAvg.toStringAsFixed(1)} km/L'
                      : '— km/L',
                  style: TextStyle(
                    color: accent,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Overall average  •  ${_logs.length} entries',
                  style: const TextStyle(
                    color: kTextSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Icon(Icons.arrow_forward_ios_rounded,
                color: accent.withValues(alpha: 0.5), size: 18),
          ],
        ),
      ),
    ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_gas_station_outlined,
              size: 72, color: kTextMuted.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          const Text(
            'No fill-ups yet',
            style: TextStyle(
                color: kTextSecondary,
                fontSize: 18,
                fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tap + to add your first entry.',
            style: TextStyle(color: kTextMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    return _ScrollAnimatedList(
      logs: _logs,
      distanceToNext: _distanceToNext,
      efficiencyMap: _efficiencyMap,
      tankLevels: _tankLevels,
      tankCapacity: _tankCapacity,
      onEdit: _goToEdit,
      onDelete: _deleteLog,
    );
  }

  void _goToAdd() {
    Navigator.push(
      context,
      SmoothPageRoute(page: const AddEntryScreen()),
    ).then((_) => _loadData());
  }

  void _goToEdit(FuelLog log) {
    Navigator.push(
      context,
      SmoothPageRoute(page: EditEntryScreen(logId: log.id)),
    ).then((_) => _loadData());
  }

  void _goToStats() {
    Navigator.push(
      context,
      SmoothPageRoute(page: const StatsScreen()),
    );
  }

  void _goToSettings() {
    Navigator.push(
      context,
      SmoothPageRoute(
        page: SettingsScreen(
          currentTheme: widget.theme,
          onThemeChanged: widget.onThemeChanged,
        ),
      ),
    ).then((_) => _loadData());
  }
}

/// A high-performance list that animates items based on scroll position.
/// Items fade/slide in on first appearance + subtle scale on scroll.
class _ScrollAnimatedList extends StatefulWidget {
  final List<FuelLog> logs;
  final int? Function(FuelLog) distanceToNext;
  final Map<String, EfficiencyResult> efficiencyMap;
  final Map<String, double> tankLevels;
  final double tankCapacity;
  final void Function(FuelLog) onEdit;
  final void Function(FuelLog) onDelete;

  const _ScrollAnimatedList({
    required this.logs,
    required this.distanceToNext,
    required this.efficiencyMap,
    required this.tankLevels,
    required this.tankCapacity,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_ScrollAnimatedList> createState() => _ScrollAnimatedListState();
}

class _ScrollAnimatedListState extends State<_ScrollAnimatedList> {
  final ScrollController _scrollController = ScrollController();

  // Track which items have already animated in (by index).
  final Set<int> _appearedItems = {};

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: widget.logs.length,
      addAutomaticKeepAlives: false,
      addRepaintBoundaries: true,
      itemBuilder: (context, index) {
        final log = widget.logs[index];
        return _ScrollAnimatedItem(
          index: index,
          alreadyVisible: _appearedItems.contains(index),
          onAppeared: () => _appearedItems.add(index),
          child: FuelLogTile(
            log: log,
            distanceToNext: widget.distanceToNext(log),
            efficiency: widget.efficiencyMap[log.id],
            tankLevel: widget.tankLevels[log.id],
            tankCapacity: widget.tankCapacity,
            onEdit: () => widget.onEdit(log),
            onDelete: () => widget.onDelete(log),
          ),
        );
      },
    );
  }
}

/// Animates a single list item: entrance fade+slide on first build,
/// then stays fully visible.
class _ScrollAnimatedItem extends StatefulWidget {
  final int index;
  final bool alreadyVisible;
  final VoidCallback onAppeared;
  final Widget child;

  const _ScrollAnimatedItem({
    required this.index,
    required this.alreadyVisible,
    required this.onAppeared,
    required this.child,
  });

  @override
  State<_ScrollAnimatedItem> createState() => _ScrollAnimatedItemState();
}

class _ScrollAnimatedItemState extends State<_ScrollAnimatedItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(curved);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(curved);

    if (widget.alreadyVisible) {
      _controller.value = 1.0; // skip animation, already seen
    } else {
      // Stagger based on index for initial load; instant for scroll reveals
      final delay = Duration(
          milliseconds: widget.index.clamp(0, 8) * 40);
      Future.delayed(delay, () {
        if (mounted) {
          _controller.forward();
          widget.onAppeared();
        }
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}
