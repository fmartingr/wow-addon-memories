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
class SystemWindowService implements WindowService {
  SystemWindowService();

  Future<void> Function()? _onClose;
  Window? _window;
  ListenerId? _listenerId;

  Window _current() {
    final window = _window ??= WindowManager.instance.getCurrent();
    if (window == null) throw StateError('The app has no native window.');
    return window;
  }

  @override
  Future<void> init({required Future<void> Function() onCloseRequested}) async {
    _onClose = onCloseRequested;
    try {
      final window = _current();
      window.minimumSize = minimumWindowSize.toNative();
      _listenerId ??= window.addListener(_onWindowEvent);
    } on Object catch (e) {
      // Without the plugin the close button closes the app, as by default.
      debugPrint('window_manager: $e');
    }
  }

  void _onWindowEvent(WindowEvent event) {
    if (event is! WindowCloseRequestedEvent) return;
    event.request.cancel();
    final close = _onClose;
    if (close == null) return;
    unawaited(
      close().catchError((Object e) => debugPrint('window_manager: $e')),
    );
  }

  @override
  Future<void> show() async {
    final window = _current();
    window.show();
    window.focus();
  }

  @override
  Future<void> hide() async {
    _current().hide();
  }

  @override
  Future<void> quit() async {
    try {
      final window = _current();
      final id = _listenerId;
      if (id != null) window.removeListener(id);
      _listenerId = null;
      if (!window.close()) exit(0);
    } on Object {
      exit(0);
    }
  }
}
