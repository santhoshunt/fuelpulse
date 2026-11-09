import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/attachment.dart';
import '../services/open_file.dart';
import '../utils/custom_pictures.dart';

/// Full-screen bills: swipe between them, pinch a photo to zoom, share one,
/// or open a PDF in another app. With [canDelete], Delete pops the bill
/// being shown so the caller removes it.
class BillViewerScreen extends StatefulWidget {
  final List<Attachment> items;
  final int initial;
  final bool canDelete;

  const BillViewerScreen({
    super.key,
    required this.items,
    this.initial = 0,
    this.canDelete = false,
  });

  @override
  State<BillViewerScreen> createState() => _BillViewerScreenState();
}

class _BillViewerScreenState extends State<BillViewerScreen> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  Attachment get _current => widget.items[_index];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _share() => SharePlus.instance.share(ShareParams(
        files: [XFile(pictureFile(_current.file).path)],
      ));

  Future<void> _openPdf(Attachment a) async {
    final ok = await openFileExternally(
        pictureFile(a.file).path, 'application/pdf');
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No app on this phone opens PDFs.')));
    }
  }

  Widget _page(Attachment a) {
    final file = pictureFile(a.file);
    if (!file.existsSync()) {
      return const Center(
          child: Text('This file is missing',
              style: TextStyle(color: Color(0xFFAAB8D4))));
    }
    if (a.isPdf) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.picture_as_pdf_outlined,
                size: 72, color: Color(0xFFF5F7FA)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _openPdf(a),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open in another app'),
            ),
          ],
        ),
      );
    }
    return InteractiveViewer(
      maxScale: 5,
      child: Center(child: Image.file(file)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0D12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0D12),
        foregroundColor: const Color(0xFFF5F7FA),
        title: Text('Bill ${_index + 1} of ${widget.items.length}'),
        actions: [
          IconButton(
              tooltip: 'Share',
              icon: const Icon(Icons.share_outlined),
              onPressed: _share),
          if (widget.canDelete)
            IconButton(
              tooltip: 'Delete',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => Navigator.pop(context, _current),
            ),
        ],
      ),
      body: PageView(
        controller: _pages,
        onPageChanged: (i) => setState(() => _index = i),
        children: [for (final a in widget.items) _page(a)],
      ),
    );
  }
}
