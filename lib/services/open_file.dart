import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';

const _channel = MethodChannel('fuelpulse/files');

/// Hands a file to whichever app on the phone opens [mime] (a PDF viewer
/// for a PDF bill). False when no app can, or off Android.
Future<bool> openFileExternally(String path, String mime) async {
  try {
    return await _channel.invokeMethod<bool>(
            'open', {'path': path, 'mime': mime}) ??
        false;
  } catch (e) {
    debugPrint('Open file failed: $e');
    return false;
  }
}
