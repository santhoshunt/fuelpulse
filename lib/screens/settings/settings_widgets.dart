import 'package:flutter/material.dart';
import '../../utils/constants.dart';

/// Building blocks shared by the Settings sections.

Widget sectionHeader(String title) {
  return Text(
    title,
    style: const TextStyle(
      color: kTextPrimary,
      fontSize: 18,
      fontWeight: FontWeight.bold,
    ),
  );
}

void showSettingsSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

/// Rounded card listing editable names, each with rename/delete buttons,
/// plus a pinned add row. Used by the Fuel Types and Pump Brands sections.
/// Delete is disabled on the last remaining item.
Widget editableListCard({
  required List<String> items,
  required Color accent,
  required String addLabel,
  required VoidCallback onAdd,
  required void Function(String) onRename,
  required void Function(String) onDelete,
  Widget Function(String)? leadingBuilder,
}) {
  return Container(
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
    ),
    child: Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0)
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Row(
              children: [
                if (leadingBuilder != null) ...[
                  leadingBuilder(items[i]),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(
                    items[i],
                    style:
                        const TextStyle(color: kTextPrimary, fontSize: 14),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.edit_outlined,
                      size: 18, color: accent.withValues(alpha: 0.7)),
                  onPressed: () => onRename(items[i]),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 18,
                      color: items.length > 1
                          ? kDanger.withValues(alpha: 0.7)
                          : kTextMuted.withValues(alpha: 0.4)),
                  onPressed:
                      items.length > 1 ? () => onDelete(items[i]) : null,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ],
        Divider(height: 1, color: Colors.white.withValues(alpha: 0.06)),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 18),
          label: Text(addLabel),
        ),
      ],
    ),
  );
}

Widget actionCard({
  required IconData icon,
  required String label,
  required VoidCallback onTap,
  required Color accent,
}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 18),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Icon(icon, color: accent, size: 28),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: kTextSecondary, fontSize: 13),
          ),
        ],
      ),
    ),
  );
}

/// Confirm dialog shared by the fuel type and pump brand deletes.
Future<bool> confirmListDelete(
    BuildContext context, String name, String body) async {
  final confirm = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('Delete "$name"?'),
      content: Text(body),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
        ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: kDanger, foregroundColor: Colors.white),
            child: const Text('Delete')),
      ],
    ),
  );
  return confirm == true;
}
