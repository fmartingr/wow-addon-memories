/// Picking and checking the WoW folder and the backup folder.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:memories_core/memories_core.dart';
import 'package:path/path.dart' as p;

import '../platform/discovery.dart';
import '../platform/folder_picker.dart';
import '../settings/settings_controller.dart';

/// The answer of [pickWowFolder].
sealed class WowPick {
  const WowPick();
}

class WowPickCancelled extends WowPick {
  const WowPickCancelled();
}

/// The user picked a flavor folder.
class WowPicked extends WowPick {
  const WowPicked(this.folder);

  final WowFolder folder;
}

/// The user picked the World of Warcraft folder; it holds [folders].
class WowPickChoices extends WowPick {
  const WowPickChoices(this.folders, this.message);

  final List<WowFolder> folders;
  final String message;
}

/// The folder cannot be gathered; [message] tells why.
class WowPickRefused extends WowPick {
  const WowPickRefused(this.message);

  final String message;
}

/// Shown when the folder picker fails to open.
const String pickerFailedText =
    'We could not open the folder picker. Try again, or restart the app.';

/// Shown when the check of a picked folder fails to run.
const String checkFailedText =
    'We could not check this folder. Try again, or choose another folder.';

/// Opens the folder picker and checks the folder the user chose.
Future<WowPick> pickWowFolder(
  FolderPicker picker,
  Discovery discovery, {
  String? initialDirectory,
}) async {
  final String? path;
  try {
    path = await picker.pickFolder(
      initialDirectory: initialDirectory,
      confirmText: 'Use this folder',
    );
  } on Object {
    return const WowPickRefused(pickerFailedText);
  }
  if (path == null) return const WowPickCancelled();
  final FlavorCheck check;
  try {
    check = await discovery.validate(path);
  } on Object {
    return const WowPickRefused(checkFailedText);
  }
  return switch (check) {
    Valid(:final folder) => WowPicked(folder),
    IsInstallFolder(:final flavors) => WowPickChoices(flavors, check.message),
    _ => WowPickRefused(check.message),
  };
}

/// The text to show when [backupRoot] cannot hold the backups of
/// [flavorDir], or null when it can. A backup root inside the World of
/// Warcraft folder, or one that holds it, is refused.
String? backupFolderProblem(String backupRoot, String? flavorDir) {
  if (flavorDir == null) return null;
  final ignoreCase = !Platform.isLinux;
  String key(String path) {
    final n = p.normalize(p.absolute(path));
    return ignoreCase ? n.toLowerCase() : n;
  }

  final root = key(backupRoot);
  final install = key(p.dirname(flavorDir));
  if (p.equals(root, install) ||
      p.isWithin(install, root) ||
      p.isWithin(root, install)) {
    return 'This folder is inside your World of Warcraft folder, or holds '
        'it. Choose a backup folder outside the game folder.';
  }
  return null;
}

void _showText(BuildContext context, String text) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// Asks for a new WoW folder and saves it. A folder that cannot be gathered
/// shows its message and is not saved.
Future<void> changeWowFolder(
  BuildContext context, {
  required SettingsController settings,
  required FolderPicker picker,
  required Discovery discovery,
}) async {
  final current = settings.settings.flavorDir;
  final pick = await pickWowFolder(
    picker,
    discovery,
    initialDirectory: current == null ? null : p.dirname(current),
  );
  if (!context.mounted) return;
  WowFolder? chosen;
  switch (pick) {
    case WowPickCancelled():
      return;
    case WowPickRefused(:final message):
      _showText(context, message);
      return;
    case WowPicked(:final folder):
      chosen = folder;
    case WowPickChoices(:final folders, :final message):
      chosen = await showDialog<WowFolder>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Choose a game version'),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(message),
            ),
            for (final f in folders)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, f),
                child: Text(f.flavor),
              ),
          ],
        ),
      );
  }
  if (chosen == null || !context.mounted) return;
  final root = settings.settings.backupRoot;
  if (root != null && backupFolderProblem(root, chosen.flavorDir) != null) {
    _showText(
      context,
      'Your backup folder is inside this World of Warcraft folder, or holds '
      'it. Choose another backup folder first, then this WoW folder.',
    );
    return;
  }
  await settings.update(
    settings.settings.copyWith(flavorDir: chosen.flavorDir),
  );
}

/// Asks for a new backup folder, warns that the old one stays as it is, and
/// saves the new one.
Future<void> changeBackupFolder(
  BuildContext context, {
  required SettingsController settings,
  required FolderPicker picker,
}) async {
  final current = settings.settings.backupRoot;
  final String? path;
  try {
    path = await picker.pickFolder(
      initialDirectory: current == null ? null : p.dirname(current),
      confirmText: 'Use this folder',
    );
  } on Object {
    if (context.mounted) _showText(context, pickerFailedText);
    return;
  }
  if (path == null || !context.mounted) return;
  final problem = backupFolderProblem(path, settings.settings.flavorDir);
  if (problem != null) {
    _showText(context, problem);
    return;
  }
  if (current != null && !p.equals(current, path)) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Use this backup folder?'),
        content: Text(
          'New gathers go to $path. Your old backup folder stays as it is. '
          'We do not move or delete it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Use this folder'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
  }
  await settings.update(settings.settings.copyWith(backupRoot: path));
}
