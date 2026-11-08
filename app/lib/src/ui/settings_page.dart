/// The settings: the folders, the switches and the version.
library;

import 'package:flutter/material.dart';
import 'package:memories_core/memories_core.dart';

import '../platform/services.dart';
import '../settings/settings_controller.dart';
import '../upload/upload_controller.dart';
import '../version.dart';
import 'folder_flow.dart';
import 'switch_tiles.dart';
import 'website_section.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.services,
    required this.settings,
    required this.upload,
  });

  final AppServices services;
  final SettingsController settings;
  final UploadController upload;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: settings,
          builder: (context, _) {
            final s = settings.settings;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: FocusTraversalGroup(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    children: [
                      if (settings.notice != null)
                        ListTile(
                          leading: const Icon(Icons.info_outline),
                          title: Text(settings.notice!),
                        ),
                      _FolderTile(
                        title: 'WoW folder',
                        path: s.flavorDir,
                        semantics: 'Change the WoW folder',
                        onChange: () => changeWowFolder(
                          context,
                          settings: settings,
                          picker: services.picker,
                          discovery: services.discovery,
                        ),
                      ),
                      _FolderTile(
                        title: 'Backup folder',
                        path: s.backupRoot,
                        semantics: 'Change the backup folder',
                        onChange: () => changeBackupFolder(
                          context,
                          settings: settings,
                          picker: services.picker,
                        ),
                      ),
                      const Divider(),
                      WatchTile(
                        value: s.watch,
                        onChanged: (v) => settings.update(
                          settings.settings.copyWith(watch: v),
                        ),
                      ),
                      StartAtLoginTile(
                        value: s.startAtLogin,
                        onChanged: (v) => settings.update(
                          settings.settings.copyWith(startAtLogin: v),
                        ),
                      ),
                      const Divider(),
                      WebsiteSection(upload: upload, settings: settings),
                      const Divider(),
                      ListTile(
                        title: const Text('Version'),
                        subtitle: Text(
                          'WoW Journey $appVersion, ${describeCore()}',
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
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
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(path ?? 'Not set'),
        const SizedBox(height: 8),
        OutlinedButton(
          onPressed: onChange,
          child: Text('Change', semanticsLabel: semantics),
        ),
      ],
    ),
  );
}
