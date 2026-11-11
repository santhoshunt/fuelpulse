import 'package:flutter/material.dart';

/// Merge-or-replace choice shared by the Drive restore and the backup file
/// import. Returns 'merge', 'replace', or null when cancelled.
Future<String?> showRestoreModeDialog(BuildContext context,
    {required String title, required int currentCount}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(
        "Merge adds what this phone doesn't already have. Replace deletes "
        'the data on this phone, including $currentCount '
        "${currentCount == 1 ? 'fill-up' : 'fill-ups'}, then restores the backup.",
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(ctx, 'merge'),
            child: const Text('Merge')),
        ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'replace'),
            child: const Text('Replace')),
      ],
    ),
  );
}
