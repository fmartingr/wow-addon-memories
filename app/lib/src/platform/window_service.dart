/// The app window: show, hide, the close button and quit.
library;

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// The narrowest window that the screens fit.
const Size minimumWindowSize = Size(480, 400);

/// Controls the one window of the app.
abstract interface class WindowService {
  /// Takes over the close button, which then calls [onCloseRequested] and
  /// leaves the window open, and sets the minimum size.
  Future<void> init({required Future<void> Function() onCloseRequested});

  /// Shows the window and brings it to the front.
  Future<void> show();

  Future<void> hide();

  /// Closes the window and ends the app.
  Future<void> quit();
}

/// The window of the system, through `window_manager`.
class SystemWindowService with WindowListener implements WindowService {
  SystemWindowService();

  Future<void> Function()? _onClose;
  Future<void>? _ready;

  // The plugin finds the native window in ensureInitialized; before it, show
  // does nothing on Windows and crashes on macOS. A copy that shows its
  // window without init, such as AlreadyRunningApp, needs it too.
  Future<void> _ensureInitialized() =>
      _ready ??= windowManager.ensureInitialized();

  @override
  Future<void> init({required Future<void> Function() onCloseRequested}) async {
    _onClose = onCloseRequested;
    try {
      await _ensureInitialized();
      windowManager.addListener(this);
      await windowManager.setPreventClose(true);
      await windowManager.setMinimumSize(minimumWindowSize);
    } on Object catch (e) {
      // Without the plugin the close button closes the app, as by default.
      debugPrint('window_manager: $e');
    }
  }

  @override
  void onWindowClose() {
    final close = _onClose;
    if (close == null) return;
    unawaited(
      close().catchError((Object e) => debugPrint('window_manager: $e')),
    );
  }

  @override
  Future<void> show() async {
    await _ensureInitialized();
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> hide() async {
    await _ensureInitialized();
    await windowManager.hide();
  }

  @override
  Future<void> quit() async {
    windowManager.removeListener(this);
    try {
      await windowManager.destroy();
    } on Object {
      exit(0);
    }
  }
}
