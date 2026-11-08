import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';

/// Building blocks shared by the Settings sections.

Widget sectionHeader(String title) {
  return Builder(
    builder: (context) => Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: TextStyle(
          color: AppColors.of(context).textSecondary,
          fontSize: 15,
          fontWeight: FontWeight.w500,
        ),
      ),
    ),
  );
}

/// One tappable row in a settings group: label, optional trailing value,
/// chevron.
class SettingsRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Widget? trailing;
  final VoidCallback onTap;

  const SettingsRow({
    super.key,
    required this.icon,
    required this.label,
    this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Icon(icon, size: 20, color: colors.primary),
              const SizedBox(width: 14),
              Expanded(
                child: Text(label,
                    style: TextStyle(color: colors.textPrimary, fontSize: 16)),
              ),
              ?trailing,
              Icon(Icons.chevron_right, color: colors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}

/// A card of [SettingsRow]s with dividers between them.
Widget settingsGroup(List<Widget> rows) {
  return Builder(builder: (context) {
    final colors = AppColors.of(context);
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0)
              Divider(
                  height: 1,
                  indent: 50,
                  endIndent: 16,
                  color: colors.cardBorder),
            rows[i],
          ],
        ],
      ),
    );
  });
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
  return Builder(builder: (context) {
  final colors = AppColors.of(context);
  return Card(
    margin: EdgeInsets.zero,
    child: Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0)
            Divider(height: 1, color: colors.cardBorder),
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
                        TextStyle(color: colors.textPrimary, fontSize: 14),
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
                          ? colors.danger.withValues(alpha: 0.7)
                          : colors.textSecondary.withValues(alpha: 0.4)),
                  onPressed:
                      items.length > 1 ? () => onDelete(items[i]) : null,
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ],
        Divider(height: 1, color: colors.cardBorder),
        TextButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add, size: 18),
          label: Text(addLabel),
        ),
      ],
    ),
  );
  });
}

Widget actionCard({
  required IconData icon,
  required String label,
  required VoidCallback onTap,
  required Color accent,
}) {
  return Builder(builder: (context) {
  final colors = AppColors.of(context);
  return Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Column(
        children: [
          Icon(icon, color: accent, size: 28),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(color: colors.textSecondary, fontSize: 13),
          ),
        ],
      ),
    ),
    ),
  );
  });
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
                backgroundColor: AppColors.of(ctx).danger,
                foregroundColor: Colors.white),
            child: const Text('Delete')),
      ],
    ),
  );
  return confirm == true;
}
