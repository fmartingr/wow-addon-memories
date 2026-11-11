/// The desktop side of the app: the tray menu, the close button, the hidden
/// start, the login entry and Quit.
library;

import 'dart:async';

import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../l10n/app_localizations.dart';
import '../gather/gather_controller.dart';
import '../l10n/app_locale.dart';
import '../platform/folder_opener.dart';
import '../platform/startup_service.dart';
import '../platform/tray_service.dart';
import '../platform/window_service.dart';
import '../settings/settings_controller.dart';
import '../viewer/viewer_launcher.dart';
import '../watch/watch_controller.dart';

/// Whether the start arguments ask for a hidden window, as the login entry
/// does.
bool startsHidden(List<String> args) => args.contains(hiddenArgument);

/// The labels of the tray menu, in order, in the language of [l].
class TrayLabels {
  TrayLabels(AppLocalizations l)
    : gatherNow = l.trayGatherNow,
      viewJourney = l.trayViewJourney,
      openWindow = l.trayOpenWindow,
      openBackupFolder = l.trayOpenBackupFolder,
      quit = l.trayQuit;

  final String gatherNow;
  final String viewJourney;
  final String openWindow;
  final String openBackupFolder;
  final String quit;
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
    required this.viewer,
    this.startHidden = false,
    Iterable<Locale> Function()? systemLocales,
  }) : _systemLocales =
           systemLocales ?? (() => PlatformDispatcher.instance.locales);

  final SettingsController settings;
  final GatherController gather;
  final WatchController watch;
  final TrayService tray;
  final WindowService window;
  final StartupService startup;
  final FolderOpener opener;
  final ViewerLauncher viewer;

  /// Whether the app started with [hiddenArgument]; the runner then left the
  /// window hidden.
  final bool startHidden;

  final Iterable<Locale> Function() _systemLocales;

  /// The language of the labels that the tray shows now.
  Locale? _trayLocale;

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
    _trayLocale = _locale();
    final texts = textsFor(_trayLocale!);
    await tray.start(_trayItems(texts), tooltip: texts.appTitle);
    _trayStarted = true;
    _onSettings();
  }

  Locale _locale() =>
      effectiveLocale(settings.settings.language, _systemLocales());

  List<TrayItem> _trayItems(AppLocalizations texts) {
    final labels = TrayLabels(texts);
    return [
      TrayItem(labels.gatherNow, () => unawaited(gatherNow())),
      TrayItem(labels.viewJourney, () => unawaited(viewJourney())),
      TrayItem(labels.openWindow, () => unawaited(openWindow())),
      TrayItem(labels.openBackupFolder, () => unawaited(openBackupFolder())),
      TrayItem(labels.quit, () => unawaited(quit())),
    ];
  }

  /// Rebuilds the tray menu when the language changed: after a change of the
  /// setting, or of the system language while the setting follows it.
  void refreshLanguage() {
    if (!_trayStarted || !settings.loaded) return;
    final locale = _locale();
    if (locale == _trayLocale) return;
    _trayLocale = locale;
    final texts = textsFor(locale);
    unawaited(tray.update(_trayItems(texts), tooltip: texts.appTitle));
  }

  void _onSettings() {
    if (!settings.loaded) return;
    refreshLanguage();
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

  /// Opens the page of the default character, in the app language. It shows
  /// the window when there is no character or the page cannot open.
  Future<void> viewJourney() async {
    final snap = gather.snapshot;
    final characters = snap.characters;
    if (characters.isEmpty) return openWindow();
    final id = characters.any((c) => c.id == snap.defaultCharacter)
        ? snap.defaultCharacter!
        : characters.first.id;
    final result = await viewer.open(id, _locale().languageCode);
    if (result is! ViewerOpened) await openWindow();
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
    try {
      await viewer.close();
    } on Object catch (e) {
      // A failed close must not keep the app from quitting.
      debugPrint('viewer: $e');
    }
    await tray.dispose();
    await window.quit();
  }

  void dispose() {
    settings.removeListener(_onSettings);
  }
}
