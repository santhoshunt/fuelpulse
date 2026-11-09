import 'package:flutter/material.dart';

/// Changes [child] when [index] changes, as a fade-through on a shared
/// axis: the old content fades out fast while drifting away and shrinking
/// a little, then the new one drifts in from the side you moved towards,
/// growing from slightly smaller as it fades in. The two never show at
/// once.
class SwitchTransition extends StatefulWidget {
  final int index;
  final Widget child;

  const SwitchTransition({super.key, required this.index, required this.child});

  @override
  State<SwitchTransition> createState() => _SwitchTransitionState();
}

class _SwitchTransitionState extends State<SwitchTransition> {
  /// 1 when the new index is to the right of the old one, else -1.
  int _dir = 1;

  @override
  void didUpdateWidget(SwitchTransition old) {
    super.didUpdateWidget(old);
    if (widget.index != old.index) _dir = widget.index > old.index ? 1 : -1;
  }

  @override
  Widget build(BuildContext context) {
    final current = ValueKey(widget.index);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 320),
      layoutBuilder: (cur, previous) => Stack(
        alignment: Alignment.topCenter,
        children: [...previous, ?cur],
      ),
      // A new closure each build, so outgoing children are rebuilt with the
      // current direction.
      transitionBuilder: (child, animation) {
        final incoming = child.key == current;
        final sign = incoming ? _dir : -_dir;
        // The outgoing child runs this animation backwards, 1 to 0: its
        // intervals sit at the top so it is gone in the first third.
        final fade = CurvedAnimation(
          parent: animation,
          curve: incoming
              ? const Interval(0.35, 1, curve: Curves.easeOut)
              : const Interval(0.7, 1, curve: Curves.easeIn),
        );
        final move = CurvedAnimation(
          parent: animation,
          curve: incoming
              ? const Interval(0.25, 1, curve: Curves.easeOutCubic)
              : const Interval(0.5, 1, curve: Curves.easeIn),
        );
        return FadeTransition(
          opacity: fade,
          child: SlideTransition(
            position: Tween(begin: Offset(0.06 * sign, 0), end: Offset.zero)
                .animate(move),
            child: ScaleTransition(
              scale: Tween(begin: 0.94, end: 1.0).animate(move),
              alignment: Alignment.topCenter,
              child: child,
            ),
          ),
        );
      },
      child: KeyedSubtree(key: current, child: widget.child),
    );
  }
}
