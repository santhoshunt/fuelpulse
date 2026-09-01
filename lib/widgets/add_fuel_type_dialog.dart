import 'package:flutter/material.dart';

/// Prompt for a name (fuel type or pump brand). Returns the typed text, or
/// null on cancel. Used by both entry screens and the Settings managers.
Future<String?> showAddFuelTypeDialog(BuildContext context,
    {String title = 'Add Fuel Type',
    String? initial,
    String hint = 'e.g. XP-95'}) {
  final controller = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(hintText: hint),
        onSubmitted: (v) => Navigator.pop(ctx, v),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel')),
        ElevatedButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save')),
      ],
    ),
  );
}
