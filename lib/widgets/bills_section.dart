import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../db/database_helper.dart';
import '../models/attachment.dart';
import '../screens/bill_viewer_screen.dart';
import '../theme/app_colors.dart';
import '../utils/custom_pictures.dart';
import '../utils/page_routes.dart';
import '../services/app_lock.dart';

/// Thumbnails of a form's bills with an Add tile. Changes stay in memory:
/// the form calls [saveBills] when it saves and [discardBills] when it is
/// closed without saving.
class BillsSection extends StatelessWidget {
  /// 'service', 'fuel' or 'paper'.
  final String ownerType;
  final List<Attachment> items;
  final ValueChanged<List<Attachment>> onChanged;

  /// The Add tile's label.
  final String addLabel;

  const BillsSection({
    super.key,
    required this.ownerType,
    required this.items,
    required this.onChanged,
    this.addLabel = 'Add',
  });

  Future<void> _add(BuildContext context) async {
    final colors = AppColors.of(context);
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (value, icon, label) in const [
              ('camera', Icons.photo_camera_outlined, 'Take a photo'),
              ('gallery', Icons.photo_library_outlined, 'Choose from gallery'),
              ('pdf', Icons.picture_as_pdf_outlined, 'Choose a PDF'),
            ])
              ListTile(
                leading: Icon(icon, color: colors.primary),
                title: Text(label),
                onTap: () => Navigator.pop(ctx, value),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (choice == null) return;
    String? path;
    if (choice == 'pdf') {
      final picked = await withoutRelock(() => FilePicker.pickFile(
          type: FileType.custom, allowedExtensions: ['pdf']));
      path = picked?.path;
    } else {
      // The long side at most 1600 px, so a tall receipt stays small too.
      final x = await withoutRelock(() => ImagePicker().pickImage(
          source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 80));
      path = x?.path;
    }
    if (path == null) return;
    final pdf = choice == 'pdf';
    final name = await importBillFile(path, pdf: pdf);
    onChanged([
      ...items,
      Attachment(
        id: Attachment.generateId(),
        ownerType: ownerType,
        ownerId: '',
        file: name,
        kind: pdf ? 'pdf' : 'image',
        createdAt: DateTime.now().toIso8601String(),
      ),
    ]);
  }

  Future<void> _open(BuildContext context, int index) async {
    final removed = await Navigator.push<Attachment>(
      context,
      SmoothPageRoute(
          page: BillViewerScreen(items: items, initial: index, canDelete: true)),
    );
    if (removed != null) {
      onChanged([for (final a in items) if (a.id != removed.id) a]);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    Widget tile({required Widget child, VoidCallback? onTap, bool dashed = false}) =>
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 64,
            height: 80,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: dashed ? Colors.transparent : colors.card,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: dashed ? colors.primary : colors.cardBorder),
            ),
            child: child,
          ),
        );
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (var i = 0; i < items.length; i++)
          Stack(
            clipBehavior: Clip.none,
            children: [
              tile(
                onTap: () => _open(context, i),
                child: items[i].isPdf
                    ? Center(
                        child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.picture_as_pdf_outlined,
                              color: colors.primary),
                          Text('PDF',
                              style: TextStyle(
                                  color: colors.primary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ],
                      ))
                    : Image.file(
                        pictureFile(items[i].file),
                        fit: BoxFit.cover,
                        cacheWidth: 200,
                        errorBuilder: (_, _, _) => Icon(
                            Icons.broken_image_outlined,
                            color: colors.textSecondary),
                      ),
              ),
              Positioned(
                top: -6,
                right: -6,
                child: Semantics(
                  button: true,
                  label: 'Remove bill',
                  child: GestureDetector(
                    onTap: () => onChanged(
                        [for (final a in items) if (a.id != items[i].id) a]),
                    child: CircleAvatar(
                      radius: 10,
                      backgroundColor: colors.textPrimary,
                      child: Icon(Icons.close, size: 13, color: colors.card),
                    ),
                  ),
                ),
              ),
            ],
          ),
        tile(
          dashed: true,
          onTap: () => _add(context),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.add, color: colors.primary),
                Text(addLabel,
                    style: TextStyle(
                        color: colors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Saves a form's bills under [ownerId]: new ones are stored, removed ones
/// are deleted with their files.
Future<void> saveBills(
    String ownerId, List<Attachment> now, List<Attachment> before) async {
  final db = DatabaseHelper();
  final keep = {for (final a in now) a.id};
  final gone = [for (final a in before) if (!keep.contains(a.id)) a];
  for (final a in gone) {
    await db.deleteAttachment(a.id);
  }
  await deletePictureFiles(gone.map((a) => a.file));
  for (final a in now) {
    await db.saveAttachment(a.copyWith(ownerId: ownerId));
  }
}

/// Deletes the files of bills added in a form that closed without saving.
Future<void> discardBills(List<Attachment> now, List<Attachment> before) {
  final saved = {for (final a in before) a.id};
  return deletePictureFiles(
      [for (final a in now) if (!saved.contains(a.id)) a.file]);
}
