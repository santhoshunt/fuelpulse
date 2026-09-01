import 'package:flutter/material.dart';
import '../utils/constants.dart';

/// One row in the picker sheet.
class PickerOption<T> {
  final T value;
  final String label;
  final Widget? leading;

  const PickerOption({required this.value, required this.label, this.leading});
}

/// What the sheet closed with: a picked option, or the footer action.
sealed class PickerResult<T> {
  const PickerResult();
}

class PickerPicked<T> extends PickerResult<T> {
  final T value;
  const PickerPicked(this.value);
}

class PickerActionTapped<T> extends PickerResult<T> {
  const PickerActionTapped();
}

/// Modern replacement for dropdown menus: a rounded modal bottom sheet with
/// a drag handle, highlighted selection, and an optional pinned footer
/// action (e.g. "Add fuel type"). Returns null when dismissed.
Future<PickerResult<T>?> showOptionPicker<T>({
  required BuildContext context,
  required String title,
  required List<PickerOption<T>> options,
  T? selected,
  String? actionLabel,
  IconData actionIcon = Icons.add,
}) {
  final accent = Theme.of(context).colorScheme.primary;

  return showModalBottomSheet<PickerResult<T>>(
    context: context,
    backgroundColor: const Color(0xFF161616),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      final maxHeight = MediaQuery.of(ctx).size.height * 0.7;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                child: Text(
                  title,
                  style: const TextStyle(
                    color: kTextPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: options.length,
                  itemBuilder: (ctx, i) {
                    final option = options[i];
                    final isSelected = option.value == selected;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () =>
                            Navigator.pop(ctx, PickerPicked<T>(option.value)),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? accent.withValues(alpha: 0.1)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(12),
                            border: isSelected
                                ? Border.all(
                                    color: accent.withValues(alpha: 0.35))
                                : null,
                          ),
                          child: Row(
                            children: [
                              if (option.leading != null) ...[
                                option.leading!,
                                const SizedBox(width: 12),
                              ],
                              Expanded(
                                child: Text(
                                  option.label,
                                  style: TextStyle(
                                    color: isSelected ? accent : kTextPrimary,
                                    fontSize: 15,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isSelected)
                                Icon(Icons.check_circle_rounded,
                                    color: accent, size: 20),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (actionLabel != null) ...[
                Divider(
                    height: 1, color: Colors.white.withValues(alpha: 0.08)),
                InkWell(
                  onTap: () =>
                      Navigator.pop(ctx, PickerActionTapped<T>()),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 16),
                    child: Row(
                      children: [
                        Icon(actionIcon, color: accent, size: 20),
                        const SizedBox(width: 10),
                        Text(
                          actionLabel,
                          style: TextStyle(
                            color: accent,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    },
  );
}

/// A form-styled tappable field that opens a picker sheet. Matches the
/// app's InputDecoration look, with a chevron instead of a dropdown arrow.
class PickerField extends StatelessWidget {
  final String label;
  final IconData icon;
  final Widget child;
  final VoidCallback onTap;

  const PickerField({
    super.key,
    required this.label,
    required this.icon,
    required this.child,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: kTextSecondary),
        ),
        child: child,
      ),
    );
  }
}
