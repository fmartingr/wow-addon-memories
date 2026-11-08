import 'package:flutter/material.dart';

import 'gather/gather_controller.dart';
import 'platform/services.dart';
import 'settings/settings_controller.dart';
import 'ui/home_page.dart';
import 'ui/wizard_page.dart';

/// The app: the wizard on the first start, else the main screen.
class WowJourneyApp extends StatefulWidget {
  const WowJourneyApp({super.key, required this.services});

  final AppServices services;

  @override
  State<WowJourneyApp> createState() => _WowJourneyAppState();
}

class _WowJourneyAppState extends State<WowJourneyApp> {
  late final SettingsController _settings = SettingsController(
    widget.services.store,
  );
  late final GatherController _gather = GatherController(
    widget.services.gather,
  );

  @override
  void initState() {
    super.initState();
    _settings.load();
  }

  @override
  void dispose() {
    _settings.dispose();
    _gather.dispose();
    super.dispose();
  }

  ThemeData _theme(Brightness brightness) => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF8A6D3B),
      brightness: brightness,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'WoW Journey',
      theme: _theme(Brightness.light),
      darkTheme: _theme(Brightness.dark),
      home: ListenableBuilder(
        listenable: _settings,
        builder: (context, _) {
          if (!_settings.loaded) {
            return const Scaffold(
              body: Center(
                child: CircularProgressIndicator(
                  semanticsLabel: 'Loading your settings',
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
          );
        },
      ),
    );
  }
}
