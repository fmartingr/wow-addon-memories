/// The tray icon and its menu.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';

/// One entry of the tray menu.
@immutable
class TrayItem {
  const TrayItem(this.label, this.onSelected);

  final String label;
  final VoidCallback onSelected;
}

/// Shows the icon of the app in the system tray, with a menu.
abstract interface class TrayService {
  /// Shows the icon with a menu of [items] and the hover text [tooltip].
  /// Returns [available].
  Future<bool> start(List<TrayItem> items, {required String tooltip});

  /// Replaces the menu and the hover text of the icon that shows, such as
  /// after a change of language. The icon stays, and [available] does not
  /// change.
  Future<void> update(List<TrayItem> items, {required String tooltip});

  /// Whether the icon shows, so that the user can open a hidden window again.
  bool get available;

  /// Removes the icon.
  Future<void> dispose();
}

/// Runs a program and returns its result, as [Process.run] does.
typedef ProcessRunner = Future<ProcessResult> Function(
  String executable,
  List<String> arguments,
);

/// Whether a Linux panel shows status notifier icons. GNOME shows none
/// without the AppIndicator extension, and the tray plugin cannot tell: it
/// only checks that the session bus exists.
Future<bool> hasStatusNotifierHost({ProcessRunner run = Process.run}) async {
  const name = 'org.kde.StatusNotifierWatcher';
  const property = 'IsStatusNotifierHostRegistered';
  final queries = [
    (
      'gdbus',
      [
        'call',
        '--session',
        '--timeout=2',
        '--dest',
        name,
        '--object-path',
        '/StatusNotifierWatcher',
        '--method',
        'org.freedesktop.DBus.Properties.Get',
        name,
        property,
      ],
    ),
    (
      'busctl',
      [
        '--user',
        '--timeout=2',
        'get-property',
        name,
        '/StatusNotifierWatcher',
        name,
        property,
      ],
    ),
  ];
  // Each tool ends its own query after 2 s; the Dart timeout is the backstop.
  for (final (exe, args) in queries) {
    try {
      final r = await run(exe, args).timeout(const Duration(seconds: 3));
      if (r.exitCode != 0) return false;
      // gdbus prints `(<true>,)`, busctl prints `b true`.
      return RegExp(r'\btrue\b').hasMatch('${r.stdout}');
    } on ProcessException {
      continue;
    } on TimeoutException {
      return false;
    }
  }
  return false;
}

/// The tray of the system, through `tray_manager`.
class SystemTrayService implements TrayService {
  SystemTrayService({this.hostCheck = hasStatusNotifierHost});

  /// Asks a Linux session for a status notifier host.
  final Future<bool> Function() hostCheck;

  TrayIcon? _icon;
  // The native menu and its items call back into Dart, so they stay
  // reachable while the icon shows. The menu before the last update stays
  // too, in case it is still open.
  final List<List<Object>> _menus = [];
  bool _available = false;

  @override
  bool get available => _available;

  @override
  Future<bool> start(List<TrayItem> items, {required String tooltip}) async {
    try {
      if (Platform.isLinux && !await hostCheck()) return _available = false;
      if (!TrayManager.instance.isSupported()) return _available = false;
      final icon = TrayIcon.create();
      final image = ImageAsset.fromAsset(
        Platform.isMacOS
            ? 'assets/tray/tray_icon_template.png'
            : 'assets/tray/tray_icon.png',
      );
      if (icon == null || image == null) return _available = false;
      icon.icon = image;
      if (Platform.isMacOS) icon.isIconTemplate = true;
      icon.setTooltip(tooltip);
      if (!_setMenu(icon, items)) return _available = false;
      _icon = icon;
      return _available = icon.setVisible(true);
    } on Object catch (e) {
      debugPrint('tray_manager: $e');
      return _available = false;
    }
  }

  /// Builds a menu of [items] and gives it to [icon]. Returns false when the
  /// native side could not build it; the old menu then stays.
  bool _setMenu(TrayIcon icon, List<TrayItem> items) {
    final menu = Menu.create();
    if (menu == null) return false;
    final keep = <Object>[menu];
    for (final item in items) {
      final entry = MenuItem.createWithLabelAndType(
        item.label,
        MenuItemType.normal,
      );
      if (entry == null) return false;
      entry.addListener((event) {
        if (event is MenuItemClickedEvent) item.onSelected();
      });
      menu.addItem(entry);
      keep.add(entry);
    }
    icon.setContextMenu(menu);
    // Linux panels open the menu on their own and report no clicks; on
    // Windows the menu is on the right button, as for other tray icons.
    icon.setContextMenuTrigger(
      Platform.isWindows
          ? ContextMenuTrigger.rightClicked
          : ContextMenuTrigger.clicked,
    );
    _menus.add(keep);
    if (_menus.length > 2) _menus.removeAt(0);
    return true;
  }

  @override
  Future<void> update(List<TrayItem> items, {required String tooltip}) async {
    final icon = _icon;
    if (!_available || icon == null) return;
    try {
      icon.setTooltip(tooltip);
      if (!_setMenu(icon, items)) {
        debugPrint('tray_manager: the new menu could not be built');
      }
    } on Object catch (e) {
      debugPrint('tray_manager: $e');
    }
  }

  @override
  Future<void> dispose() async {
    _available = false;
    try {
      _icon?.dispose();
    } on Object catch (e) {
      debugPrint('tray_manager: $e');
    }
    _icon = null;
    _menus.clear();
  }
}
