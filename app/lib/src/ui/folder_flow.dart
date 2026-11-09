/// Picking and checking the WoW folder and the backup folder.
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:memories_core/memories_core.dart';
import 'package:path/path.dart' as p;

import '../../l10n/app_localizations.dart';
import '../platform/discovery.dart';
import '../platform/folder_picker.dart';
import '../settings/settings_controller.dart';
import 'messages.dart';

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

/// The user picked the World of Warcraft folder; it holds [folders]. [check]
/// says so in words.
class WowPickChoices extends WowPick {
  const WowPickChoices(this.folders, this.check);

  final List<WowFolder> folders;
  final FlavorCheck check;
}

/// Why [WowPickRefused] refused the folder.
enum PickRefusal {
  /// The folder picker failed to open.
  pickerFailed,

  /// The check of the picked folder failed to run.
  checkFailed,

  /// The check found that the folder cannot be gathered.
  flavor,
}

/// The folder cannot be gathered. [check] says why when [reason] is
/// [PickRefusal.flavor].
class WowPickRefused extends WowPick {
  const WowPickRefused(this.reason, [this.check])
    : assert((reason == PickRefusal.flavor) == (check != null));

  final PickRefusal reason;
  final FlavorCheck? check;
}

/// The text that tells the user about [pick], or null when it needs none.
String? pickText(AppLocalizations l, WowPick pick) => switch (pick) {
  WowPickChoices(:final check) => flavorCheckText(l, check),
  WowPickRefused(reason: PickRefusal.pickerFailed) => l.pickerFailed,
  WowPickRefused(reason: PickRefusal.checkFailed) => l.checkFailed,
  WowPickRefused(:final check?) => flavorCheckText(l, check),
  _ => null,
};

/// Opens the folder picker and checks the folder the user chose.
Future<WowPick> pickWowFolder(
  FolderPicker picker,
  Discovery discovery, {
  required String confirmText,
  String? initialDirectory,
}) async {
  final String? path;
  try {
    path = await picker.pickFolder(
      initialDirectory: initialDirectory,
      confirmText: confirmText,
    );
  } on Object {
    return const WowPickRefused(PickRefusal.pickerFailed);
  }
  if (path == null) return const WowPickCancelled();
  final FlavorCheck check;
  try {
    check = await discovery.validate(path);
  } on Object {
    return const WowPickRefused(PickRefusal.checkFailed);
  }
  return switch (check) {
    Valid(:final folder) => WowPicked(folder),
    IsInstallFolder(:final flavors) => WowPickChoices(flavors, check),
    _ => WowPickRefused(PickRefusal.flavor, check),
  };
}

/// Whether [backupRoot] cannot hold the backups of [flavorDir]: a backup root
/// inside the World of Warcraft folder, or one that holds it, is refused.
bool backupFolderOverlaps(String backupRoot, String? flavorDir) {
  if (flavorDir == null) return false;
  final ignoreCase = !Platform.isLinux;
  String key(String path) {
    final n = p.normalize(p.absolute(path));
    return ignoreCase ? n.toLowerCase() : n;
  }

  final root = key(backupRoot);
  final install = key(p.dirname(flavorDir));
  return p.equals(root, install) ||
      p.isWithin(install, root) ||
      p.isWithin(root, install);
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
    confirmText: AppLocalizations.of(context).useThisFolder,
    initialDirectory: current == null ? null : p.dirname(current),
  );
  if (!context.mounted) return;
  WowFolder? chosen;
  switch (pick) {
    case WowPickCancelled():
      return;
    case WowPickRefused():
      _showText(context, pickText(AppLocalizations.of(context), pick)!);
      return;
    case WowPicked(:final folder):
      chosen = folder;
    case WowPickChoices(:final folders):
      chosen = await showDialog<WowFolder>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(AppLocalizations.of(context).chooseGameVersion),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(pickText(AppLocalizations.of(context), pick)!),
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
  if (root != null && backupFolderOverlaps(root, chosen.flavorDir)) {
    _showText(context, AppLocalizations.of(context).backupInsideWowFirst);
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
      confirmText: AppLocalizations.of(context).useThisFolder,
    );
  } on Object {
    if (context.mounted) {
      _showText(context, AppLocalizations.of(context).pickerFailed);
    }
    return;
  }
  if (path == null || !context.mounted) return;
  if (backupFolderOverlaps(path, settings.settings.flavorDir)) {
    _showText(context, AppLocalizations.of(context).backupInsideWow);
    return;
  }
  if (current != null && !p.equals(current, path)) {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        final l = AppLocalizations.of(context);
        return AlertDialog(
          title: Text(l.useBackupTitle),
          content: Text(l.useBackupBody(path!)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l.useThisFolder),
            ),
          ],
        );
      },
    );
    if (ok != true || !context.mounted) return;
  }
  // The signature of the last gather belongs to the old backup folder; a new
  // one holds none of that data, so Watch gathers into it at its next polls.
  await settings.update(
    settings.settings.copyWith(
      backupRoot: path,
      clearLastSignature: current == null || !p.equals(current, path),
    ),
  );
}
