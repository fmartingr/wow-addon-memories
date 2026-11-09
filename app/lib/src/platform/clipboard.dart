/// The system clipboard, as a function so that tests pass a fake.
library;

import 'package:flutter/services.dart';

/// Puts a text on the clipboard.
typedef CopyText = Future<void> Function(String text);

/// Puts [text] on the clipboard of the system.
Future<void> copyToClipboard(String text) =>
    Clipboard.setData(ClipboardData(text: text));
