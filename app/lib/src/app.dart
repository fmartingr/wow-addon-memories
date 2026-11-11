import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import 'gather/gather_controller.dart';
import 'l10n/app_locale.dart';
import 'platform/services.dart';
import 'settings/settings_controller.dart';
import 'shell/shell_controller.dart';
import 'theme/ak_theme.dart';
import 'ui/home_page.dart';
import 'upload/upload_controller.dart';
import 'ui/wizard_page.dart';
import 'watch/watch_controller.dart';

/// The app: the wizard on the first start, else the main screen.
class WowJourneyApp extends StatefulWidget {
  const WowJourneyApp({
    super.key,
    required this.services,
    this.startHidden = false,
    this.showRequests,
  });

  final AppServices services;

  /// Whether the app started with `--hidden`, as at login.
  final bool startHidden;

  /// Fires when a later start of the app asks for the window.
  final Stream<void>? showRequests;

  @override
  State<WowJourneyApp> createState() => _WowJourneyAppState();
}

class _WowJourneyAppState extends State<WowJourneyApp>
    with WidgetsBindingObserver {
  late final SettingsController _settings = SettingsController(
    widget.services.store,
  );
  late final GatherController _gather = GatherController(
    widget.services.gather,
  );
  late final UploadController _upload = UploadController(
    service: widget.services.uploader,
    settings: _settings,
    gather: _gather,
    clock: widget.services.clock,
  );
  late final WatchController _watch = WatchController(
    settings: _settings,
    gather: _gather,
    signature: widget.services.signature,
    clock: widget.services.clock,
  );
  late final ShellController _shell = ShellController(
    settings: _settings,
    gather: _gather,
    watch: _watch,
    tray: widget.services.tray,
    window: widget.services.window,
    startup: widget.services.startup,
    opener: widget.services.opener,
    viewer: widget.services.viewer,
    startHidden: widget.startHidden,
  );
  StreamSubscription<void>? _showRequests;

  // MaterialApp rebuilds on each settings save, so the theme is built once.
  final ThemeData _theme = buildAkTheme();

  @override
  void initState() {
    super.initState();
    // Made now, not on first use, so it sees every gather and settings load.
    _upload;
    WidgetsBinding.instance.addObserver(this);
    _settings.addListener(_syncWatch);
    _settings.addListener(_syncViewer);
    _settings.load();
    _shell.start();
    _showRequests = widget.showRequests?.listen((_) => _shell.openWindow());
  }

  @override
  void didChangeLocales(List<Locale>? locales) => _shell.refreshLanguage();

  /// Watch runs while its switch is on and both folders are set: from the
  /// app start, the wizard Finish, or the switch.
  void _syncWatch() {
    final s = _settings.settings;
    if (_settings.loaded &&
        s.wizardDone &&
        s.watch &&
        s.flavorDir != null &&
        s.backupRoot != null) {
      _watch.start();
    } else {
      _watch.stop();
    }
  }

  void _syncViewer() {
    widget.services.viewer.backupRoot = _settings.settings.backupRoot;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _showRequests?.cancel();
    _shell.dispose();
    _settings.removeListener(_syncWatch);
    _settings.removeListener(_syncViewer);
    _watch.dispose();
    _upload.dispose();
    _settings.dispose();
    _gather.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) => MaterialApp(
        onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
        theme: _theme,
        locale: settingLocale(_settings.settings.language),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        localeListResolutionCallback: (locales, _) =>
            resolveAppLocale(locales ?? const []),
        home: _home(),
      ),
    );
  }

  Widget _home() {
    return ListenableBuilder(
      listenable: _settings,
      builder: (context, _) {
        if (!_settings.loaded) {
          return Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                semanticsLabel: AppLocalizations.of(context).loadingSettings,
              ),
            ),
          );
        }
        if (!_settings.settings.wizardDone) {
          return WizardPage(
            services: widget.services,
            initial: _settings.settings,
            notice: _settings.notice,
            onFinish: _settings.update,
          );
        }
        return HomePage(
          services: widget.services,
          settings: _settings,
          gather: _gather,
          watch: _watch,
          upload: _upload,
        );
      },
    );
  }
}
