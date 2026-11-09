/// The settings: the folders, the switches, the language and the version.
library;

import 'package:flutter/material.dart';
import 'package:memories_core/memories_core.dart';

import '../../l10n/app_localizations.dart';
import '../l10n/app_locale.dart';
import '../platform/services.dart';
import '../settings/settings_controller.dart';
import '../version.dart';
import 'folder_flow.dart';
import 'switch_tiles.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({
    super.key,
    required this.services,
    required this.settings,
  });

  final AppServices services;
  final SettingsController settings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final s = settings.settings;
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FolderTile(
                  title: l.wowFolderTitle,
                  path: s.flavorDir,
                  semantics: l.changeWowFolderSemantics,
                  onChange: () => changeWowFolder(
                    context,
                    settings: settings,
                    picker: services.picker,
                    discovery: services.discovery,
                  ),
                ),
                _FolderTile(
                  title: l.backupFolderTitle,
                  path: s.backupRoot,
                  semantics: l.changeBackupFolderSemantics,
                  onChange: () => changeBackupFolder(
                    context,
                    settings: settings,
                    picker: services.picker,
                  ),
                ),
                const Divider(),
                WatchTile(
                  value: s.watch,
                  onChanged: (v) =>
                      settings.update(settings.settings.copyWith(watch: v)),
                ),
                StartAtLoginTile(
                  value: s.startAtLogin,
                  onChanged: (v) => settings.update(
                    settings.settings.copyWith(startAtLogin: v),
                  ),
                ),
                ListTile(
                  title: Text(l.languageTitle),
                  trailing: DropdownButton<String?>(
                    key: const ValueKey('language'),
                    value: s.language,
                    onChanged: (code) => settings.update(
                      settings.settings.copyWith(
                        language: code,
                        clearLanguage: code == null,
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: null,
                        child: Text(l.languageSystem),
                      ),
                      for (final code in appLanguageCodes)
                        DropdownMenuItem(
                          value: code,
                          child: Text(appLanguageNames[code]!),
                        ),
                    ],
                  ),
                ),
                const Divider(),
                ListTile(
                  title: Text(l.versionTitle),
                  subtitle: Text(
                    l.versionText(appVersion, describeCore()),
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FolderTile extends StatelessWidget {
  const _FolderTile({
    required this.title,
    required this.path,
    required this.semantics,
    required this.onChange,
  });

  final String title;
  final String? path;
  final String semantics;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(path ?? l.notSet),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: onChange,
            child: Text(l.change, semanticsLabel: semantics),
          ),
        ],
      ),
    );
  }
}
