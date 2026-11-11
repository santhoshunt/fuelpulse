import 'package:flutter/material.dart';

/// For forms that save with a button: Back with unsaved edits asks
/// "Discard changes?" instead of dropping them. Back without edits leaves at
/// once, and a save's own Navigator.pop is not affected.
mixin DiscardGuard<T extends StatefulWidget> on State<T> {
  String? _baseline;

  /// Every value the form holds now, as one string.
  String formSnapshot();

  /// Remembers the form as it opened; call once its values are loaded.
  void markClean() => _baseline = formSnapshot();

  bool get hasEdits => _baseline != null && formSnapshot() != _baseline;

  /// Wraps the form's Scaffold.
  Widget guard(Widget child) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) async {
          if (didPop) return;
          if (!hasEdits || await _askDiscard()) {
            if (mounted) Navigator.of(context).pop();
          }
        },
        child: child,
      );

  Future<bool> _askDiscard() async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text("What you changed here isn't saved yet."),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Keep editing')),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(
                  foregroundColor: Theme.of(ctx).colorScheme.error),
              child: const Text('Discard'),
            ),
          ],
        ),
      ) ==
      true;
}
