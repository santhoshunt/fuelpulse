import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../db/database_helper.dart';
import '../models/fuel_log.dart';
import 'custom_pictures.dart' show deletePictureFiles;

/// Ticks after an Undo puts deleted rows back. The app's tabs reload on it
/// through AppShell; screens that are not tabs listen to it themselves.
final dataRestored = ValueNotifier<int>(0);

/// Deletes at once and offers Undo for a few seconds, instead of asking
/// first. [rows] names what the delete removes (table to where clause and
/// arguments), read before [delete] runs so Undo can write it back.
/// [delete] returns the picture files it freed; they are removed only once
/// Undo is gone, so an undone delete keeps its bills and photos.
/// [changed] runs after the delete and again after an Undo, to refresh
/// reminders. After an Undo [dataRestored] also ticks, so whatever shows the
/// data reads it again, even when the page that deleted it has closed.
/// Returns once the delete is done; Undo stays offered after that.
Future<void> deleteWithUndo(
  BuildContext context, {
  required String message,
  required Map<String, (String, List<Object?>)> rows,
  required Future<List<String>> Function() delete,
  Future<void> Function()? changed,
}) async {
  // The app-wide messenger, so Undo outlives a page that closes after it.
  final messenger = ScaffoldMessenger.of(context);
  final db = DatabaseHelper();
  final saved = await db.snapshotRows(rows);
  final files = await delete();
  await changed?.call();
  messenger.hideCurrentSnackBar();
  final bar = messenger.showSnackBar(SnackBar(
    content: Text(message),
    // A bar with an action stays until dismissed unless told otherwise.
    persist: false,
    duration: const Duration(seconds: 6),
    action: SnackBarAction(label: 'Undo', onPressed: () {}),
  ));
  unawaited(bar.closed.then((reason) async {
    if (reason == SnackBarClosedReason.action) {
      await db.restoreRows(saved);
      await changed?.call();
      dataRestored.value++;
    } else {
      await deletePictureFiles(files);
    }
  }));
}

/// Deletes a fill-up with its bills and photos, with Undo.
Future<void> deleteFillUpWithUndo(BuildContext context, FuelLog log,
    {Future<void> Function()? changed}) {
  final at = DateTime.tryParse(log.timestamp);
  return deleteWithUndo(
    context,
    message: at == null
        ? 'Fill-up deleted'
        : 'Fill-up of ${DateFormat('d MMM').format(at)} deleted',
    rows: {
      'fuel_logs': ('id = ?', [log.id]),
      'attachments': attachmentsOf('fuel', log.id),
    },
    delete: () => DatabaseHelper().deleteLog(log.id),
    changed: changed,
  );
}

/// Owner rows for a record that can have bills or photos attached.
(String, List<Object?>) attachmentsOf(String ownerType, String id) =>
    ('ownerType = ? AND ownerId = ?', [ownerType, id]);
