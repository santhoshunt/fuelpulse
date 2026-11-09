import 'package:flutter/material.dart';

import '../models/vehicle.dart';
import '../theme/app_colors.dart';
import '../utils/vehicle_manager.dart';
import 'papers_screen.dart';
import 'service_screen.dart';
import 'trips_screen.dart';

/// The Garage tab: the active vehicle's services, trips and papers side by
/// side. Swipe between them, or tap a label; the switch's highlight follows
/// the swipe.
class GarageScreen extends StatefulWidget {
  final ValueNotifier<int> reload;

  /// Which list shows: 0 Service, 1 Trips, 2 Papers. AppShell sets it from
  /// a link.
  final ValueNotifier<int> section;

  const GarageScreen({super.key, required this.reload, required this.section});

  @override
  State<GarageScreen> createState() => _GarageScreenState();
}

class _GarageScreenState extends State<GarageScreen> {
  static const _labels = ['Service', 'Trips', 'Papers'];
  static const _addLabels = ['Add service', 'Start a trip', 'Add paper'];
  static const _slide = Duration(milliseconds: 320);

  /// One per list: the + bumps the one for the list on show.
  final _addTaps = [for (var i = 0; i < 3; i++) ValueNotifier<int>(0)];
  late final _pages = PageController(initialPage: _section);
  Vehicle? _vehicle;

  int get _section => widget.section.value.clamp(0, _labels.length - 1);

  @override
  void initState() {
    super.initState();
    widget.reload.addListener(_load);
    widget.section.addListener(_onSection);
    _load();
  }

  @override
  void dispose() {
    widget.reload.removeListener(_load);
    widget.section.removeListener(_onSection);
    for (final n in _addTaps) {
      n.dispose();
    }
    _pages.dispose();
    super.dispose();
  }

  /// A link (or a swipe) changed the section: slide there if not already.
  void _onSection() {
    if (_pages.hasClients && (_pages.page?.round() ?? _section) != _section) {
      _pages.animateToPage(_section,
          duration: _slide, curve: Curves.easeOutCubic);
    }
    setState(() {});
  }

  void _goTo(int i) =>
      _pages.animateToPage(i, duration: _slide, curve: Curves.easeOutCubic);

  Future<void> _load() async {
    final v = await loadActiveVehicle();
    if (mounted) setState(() => _vehicle = v);
  }

  /// Service, Trips, Papers, with a highlight that sits under the page in
  /// view, moving with the finger mid-swipe.
  Widget _switch(AppColors colors) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
            colors.textPrimary.withValues(alpha: 0.07), colors.card),
        borderRadius: BorderRadius.circular(12),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth / _labels.length;
          return AnimatedBuilder(
            animation: _pages,
            builder: (context, _) {
              final page = _pages.hasClients && _pages.position.haveDimensions
                  ? _pages.page ?? _section.toDouble()
                  : _section.toDouble();
              return SizedBox(
                height: 34,
                child: Stack(
                  children: [
                    Positioned(
                      left: page * w,
                      width: w,
                      top: 0,
                      bottom: 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.card,
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < _labels.length; i++)
                          Expanded(
                            child: Semantics(
                              button: true,
                              selected: page.round() == i,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _goTo(i),
                                child: Center(
                                  child: Text(_labels[i],
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Color.lerp(
                                            colors.textSecondary,
                                            colors.textPrimary,
                                            (1 - (page - i).abs())
                                                .clamp(0.0, 1.0)),
                                        fontWeight: (page - i).abs() < 0.5
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      )),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final section = _section;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Garage',
                                style: TextStyle(
                                    color: colors.textPrimary,
                                    fontSize: 34,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.5)),
                            Text(_vehicle?.name ?? '',
                                style: TextStyle(
                                    color: colors.textSecondary,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                      Material(
                        color: colors.card,
                        shape: CircleBorder(
                            side: BorderSide(color: colors.cardBorder)),
                        child: IconButton(
                          tooltip: _addLabels[section],
                          icon: Icon(Icons.add, color: colors.primary),
                          onPressed: () => _addTaps[section].value++,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _switch(colors),
                ],
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) {
                  if (widget.section.value != i) widget.section.value = i;
                },
                children: [
                  _KeepAlive(
                      child: ServiceScreen(
                          reload: widget.reload, addTaps: _addTaps[0])),
                  _KeepAlive(
                      child: TripsScreen(
                          reload: widget.reload, addTaps: _addTaps[1])),
                  _KeepAlive(
                      child: PapersScreen(
                          reload: widget.reload, addTaps: _addTaps[2])),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Keeps a page built while it is swiped off screen, so each list keeps its
/// scroll position and its + listener, and doesn't reload on every swipe.
class _KeepAlive extends StatefulWidget {
  final Widget child;

  const _KeepAlive({required this.child});

  @override
  State<_KeepAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<_KeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
