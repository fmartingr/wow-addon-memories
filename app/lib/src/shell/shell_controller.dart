/// The desktop side of the app: the tray menu, the close button, the hidden
/// start, the login entry and Quit.
library;

import 'dart:async';

import '../gather/gather_controller.dart';
import '../platform/folder_opener.dart';
import '../platform/startup_service.dart';
import '../platform/tray_service.dart';
import '../platform/window_service.dart';
import '../settings/settings_controller.dart';
import '../watch/watch_controller.dart';

/// Whether the start arguments ask for a hidden window, as the login entry
/// does.
bool startsHidden(List<String> args) => args.contains(hiddenArgument);

/// The labels of the tray menu, in order.
abstract final class TrayLabels {
  static const String gatherNow = 'Gather now';
  static const String openWindow = 'Open window';
  static const String openBackupFolder = 'Open backup folder';
  static const String quit = 'Quit';
}

/// Ties the tray, the window and the login entry to the settings, Gather
/// and Watch.
class ShellController {
  ShellController({
    required this.settings,
    required this.gather,
    required this.watch,
    required this.tray,
    required this.window,
    required this.startup,
    required this.opener,
    this.startHidden = false,
  });

  final SettingsController settings;
  final GatherController gather;
  final WatchController watch;
  final TrayService tray;
  final WindowService window;
  final StartupService startup;
  final FolderOpener opener;

  /// Whether the app started with [hiddenArgument]; the runner then left the
  /// window hidden.
  final bool startHidden;

  bool _trayStarted = false;
  bool _shownAtStart = false;
  bool _settingsSeen = false;
  bool _quitting = false;

  /// The Start at login value given to [startup] last, or null before the
  /// first one.
  bool? _appliedStartAtLogin;

  /// Starts the tray and takes over the close button. Call it once.
  Future<void> start() async {
    settings.addListener(_onSettings);
    _onSettings();
    await window.init(onCloseRequested: onCloseRequested);
    await tray.start([
      TrayItem(TrayLabels.gatherNow, () => unawaited(gatherNow())),
      TrayItem(TrayLabels.openWindow, () => unawaited(openWindow())),
      TrayItem(
        TrayLabels.openBackupFolder,
        () => unawaited(openBackupFolder()),
      ),
      TrayItem(TrayLabels.quit, () => unawaited(quit())),
    ]);
    _trayStarted = true;
    _onSettings();
  }

  void _onSettings() {
    if (!settings.loaded) return;
    final s = settings.settings;
    if (_trayStarted && startHidden && !_shownAtStart) {
      _shownAtStart = true;
      // The wizard needs the window, and with no tray icon a hidden window
      // could never be opened again.
      if (!s.wizardDone || !tray.available) unawaited(window.show());
    }
    if (!_settingsSeen) {
      _settingsSeen = true;
      if (!s.wizardDone) return;
      _appliedStartAtLogin = s.startAtLogin;
      // The app path changes after an update, so an entry on is written
      // again at each start.
      if (s.startAtLogin) unawaited(startup.apply(true));
      return;
    }
    if (!s.wizardDone || _appliedStartAtLogin == s.startAtLogin) return;
    _appliedStartAtLogin = s.startAtLogin;
    unawaited(startup.apply(s.startAtLogin));
  }

  /// The close button: hide to the tray, or quit when there is no tray.
  Future<void> onCloseRequested() async {
    if (tray.available) {
      await window.hide();
    } else {
      await quit();
    }
  }

  /// Gathers now, or shows the window when the folders are not set yet. It
  /// leaves a hidden window hidden.
  Future<void> gatherNow() async {
    final s = settings.settings;
    if (!s.wizardDone || s.flavorDir == null || s.backupRoot == null) {
      return openWindow();
    }
    await gather.gatherNow(flavorDir: s.flavorDir!, backupRoot: s.backupRoot!);
  }

  Future<void> openWindow() => window.show();

  /// Opens the backup folder, or shows the window when there is none yet.
  Future<void> openBackupFolder() async {
    final root = settings.settings.backupRoot;
    if (root == null || !await opener.open(root)) await openWindow();
  }

  /// Stops Watch, removes the tray icon and ends the app.
  Future<void> quit() async {
    if (_quitting) return;
    _quitting = true;
    watch.stop();
    await tray.dispose();
    await window.quit();
  }

  void dispose() {
    settings.removeListener(_onSettings);
  }
}
