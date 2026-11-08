/// The plain English text of each gather problem and the fix it offers.
library;

import 'package:memories_core/memories_core.dart';

/// A button that a problem offers to fix it.
enum IssueFix {
  chooseWowFolder('Choose folder'),
  chooseBackupFolder('Choose backup folder'),
  openLatest('Open latest data'),
  tryAgain('Try again');

  const IssueFix(this.label);

  final String label;
}

/// Shown when the gather found no character with Memories data.
const String noDataText =
    'No Memories data yet. Play with the Memories addons on, then log out.';

/// Shown when the saved WoW folder is gone.
const String wowFolderGoneText =
    'We cannot find your WoW folder any more. It may have moved, or its drive '
    'is not connected. Choose the folder again.';

/// The hint about when the game writes its files.
const String saveHintText =
    'The game saves your journey when you log out or type /reload.';

/// What happened and what to do, for [code].
String issueText(GatherIssueCode code) => switch (code) {
  GatherIssueCode.noWtf =>
    'This folder has no WoW game files. Choose the folder of one game '
        'version, such as _retail_.',
  GatherIssueCode.noData => noDataText,
  GatherIssueCode.damagedFile =>
    'A saved file could not be read, so we skipped it. Log in with that '
        'character, log out, then try again.',
  GatherIssueCode.accountSkipped =>
    'The Memories file of an account is missing or damaged, so we skipped '
        'its characters. Log in once, log out, then try again.',
  GatherIssueCode.characterFailed =>
    'We could not update the data of one character, so we left it as it '
        'was. Check its folder in the latest data, then try again.',
  GatherIssueCode.overlap =>
    'The backup folder is inside the game files. Choose a backup folder '
        'outside the World of Warcraft folder.',
  GatherIssueCode.lockHeld =>
    'Another gather is running on this backup folder. Wait until it ends, '
        'then try again.',
  GatherIssueCode.notWritable =>
    'We cannot write to the backup folder. Check that its drive is connected '
        'and has free space, or choose another backup folder.',
  GatherIssueCode.badIndex =>
    'The file index.json in the latest data is damaged. Move it out of the '
        'folder, then try again.',
  GatherIssueCode.badDefault =>
    'The first character to show is not in your data. Try again.',
  GatherIssueCode.skippedFile =>
    'A saved file had no Memories data or belonged to another character, so '
        'we skipped it.',
  GatherIssueCode.duplicateGuid =>
    'Two folders hold the same character. We kept the one you played last.',
  GatherIssueCode.backupFailed =>
    'We could not copy a saved file into the backup folder. Check that its '
        'drive has free space, then try again.',
  GatherIssueCode.screenshotFailed =>
    'We could not copy a screenshot. Check that the drive has free space, '
        'then try again.',
  GatherIssueCode.ioError =>
    'A file could not be read or written, so the gather stopped. Check that '
        'your drives are connected and have free space, then try again.',
};

/// The fix that [code] offers, or null when there is nothing to do.
IssueFix? issueFix(GatherIssueCode code) => switch (code) {
  GatherIssueCode.noWtf => IssueFix.chooseWowFolder,
  GatherIssueCode.overlap ||
  GatherIssueCode.notWritable => IssueFix.chooseBackupFolder,
  GatherIssueCode.badIndex ||
  GatherIssueCode.characterFailed => IssueFix.openLatest,
  GatherIssueCode.damagedFile ||
  GatherIssueCode.accountSkipped ||
  GatherIssueCode.lockHeld ||
  GatherIssueCode.badDefault ||
  GatherIssueCode.backupFailed ||
  GatherIssueCode.screenshotFailed ||
  GatherIssueCode.ioError => IssueFix.tryAgain,
  GatherIssueCode.noData ||
  GatherIssueCode.skippedFile ||
  GatherIssueCode.duplicateGuid => null,
};

/// [bytes] as a short size, such as `12.3 MB`.
String formatSize(int bytes) {
  const units = ['bytes', 'KB', 'MB', 'GB', 'TB'];
  var v = bytes.toDouble();
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return i == 0 ? '$bytes bytes' : '${v.toStringAsFixed(1)} ${units[i]}';
}

/// [t] as `14:32` when it is on the day of [now], else `2026-11-07 14:32`.
String formatTime(DateTime t, DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  final time = '${two(t.hour)}:${two(t.minute)}';
  if (t.year == now.year && t.month == now.month && t.day == now.day) {
    return time;
  }
  return '${t.year}-${two(t.month)}-${two(t.day)} $time';
}

const Map<String, String> _classNames = {
  'DEATHKNIGHT': 'Death Knight',
  'DEMONHUNTER': 'Demon Hunter',
};

/// The game class token [token], such as `HUNTER`, as `Hunter`.
String className(String token) {
  final known = _classNames[token.toUpperCase()];
  if (known != null) return known;
  if (token.isEmpty) return token;
  return token[0].toUpperCase() + token.substring(1).toLowerCase();
}
