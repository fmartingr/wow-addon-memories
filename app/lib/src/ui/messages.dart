/// The plain English text of each gather problem and the fix it offers, and
/// of the website upload.
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

/// The status line while Watch is on.
const String watchingText = 'Watching for changes';

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

/// The title of the Website section and card.
const String websiteTitle = 'Website';

/// The title of the registration panel of the Website tab.
const String websiteRegistrationTitle = 'Registration';

/// The line that says what a character link means.
const String unlistedText =
    'Your character pages are unlisted: anybody with the link can open them.';

/// What to do after a reinstall, which makes a new key.
const String lostKeyText =
    'If you reinstall the app, ask the website admin to move your characters '
    'to your new key.';

const String websiteAddressLabel = 'Website address';
const String checkSiteLabel = 'Check';
const String inviteCodeLabel = 'Invite code';
const String registerLabel = 'Register';
const String uploadSwitchTitle = 'Upload';
const String uploadSwitchSubtitle =
    'Send your journey to the website after each gather.';
const String uploadNowLabel = 'Upload now';
const String uploadingLabel = 'Uploading…';
const String uploadPausedText =
    'Upload paused. It continues after the next gather.';
const String requestScreenshotsLabel = 'Request screenshots';
const String copyLinkLabel = 'Copy link';
const String removeFromWebsiteLabel = 'Remove from website';
const String linkCopiedText = 'Link copied';
const String cancelLabel = 'Cancel';
const String removeLabel = 'Remove';

/// The site as people read it: `example.com`, or `localhost:8080`.
String siteLabel(String site) {
  try {
    return parseSite(site).authority;
  } on FormatException {
    return site;
  }
}

/// What a successful check of the website shows.
String siteFoundText(SiteInfo info) => info.registration == 'open'
    ? 'Found ${info.name}. Anybody can register here.'
    : 'Found ${info.name}. You need an invite code from the website admin to '
          'register.';

/// Shown when the website answered, but not as a Memories website.
const String notAMemoriesSiteText =
    'This address does not look like a Memories website. Check the address.';

/// The registration line of the settings.
String registeredText(String site) => 'Registered on ${siteLabel(site)}.';

String notRegisteredText(String site) =>
    'Not registered on ${siteLabel(site)}. Register to upload your journey.';

String fingerprintText(String fingerprint) => 'Your key: $fingerprint';

/// The text of the screenshot state of the key.
String screenshotsText(String state) => switch (state) {
  'pending' => 'Waiting for the website admin to approve your screenshots.',
  'approved' => 'Your screenshots are uploaded with your journey.',
  'denied' =>
    'The website admin did not approve screenshots. You can ask again.',
  _ => 'Screenshots are not uploaded. Ask the website admin to approve them.',
};

/// Shown on the card when the key is not registered.
String cardNotRegisteredText(String site) =>
    'You are not registered on ${siteLabel(site)}. Register below to share '
    'your journey.';

const String cardUploadOffText =
    'Upload is off. Turn on the Upload switch below to send your journey.';

/// The text under the progress bar of a running upload.
String uploadProgressText(int done, int total) =>
    total <= 0 ? uploadingLabel : 'Uploading $done of $total';

/// The line about the last upload of this run.
String lastUploadText(DateTime? time, DateTime now) => time == null
    ? 'Nothing uploaded yet.'
    : 'Last upload ${formatTime(time, now)}';

/// The result of one upload, in a sentence.
String syncSummaryText(SyncReport report) {
  var sent = 0;
  var failed = 0;
  var shots = 0;
  var shotsFailed = 0;
  var removed = 0;
  for (final c in report.characters) {
    switch (c.status) {
      case SyncStatus.uploaded:
        sent++;
      case SyncStatus.unchanged:
        break;
      case SyncStatus.failed:
        failed++;
      case SyncStatus.removed:
        removed++;
    }
    shots += c.shots.uploaded;
    shotsFailed += c.shots.errors.length;
  }
  final parts = [
    if (sent > 0) 'Uploaded ${_count(sent, '1 character', 'characters')}',
    if (shots > 0) 'sent ${_count(shots, '1 screenshot', 'screenshots')}',
    if (sent == 0 && shots == 0 && failed == 0 && shotsFailed == 0)
      'Everything is up to date',
    if (removed > 0)
      'skipped ${_count(removed, '1 removed character', 'removed characters')} '
          '(Upload now sends ${removed == 1 ? 'it' : 'them'} again)',
    if (failed > 0) '${_count(failed, '1 character', 'characters')} failed',
    if (shotsFailed > 0)
      '${_count(shotsFailed, '1 screenshot', 'screenshots')} failed',
  ];
  final text = parts.join(', ');
  return '${text[0].toUpperCase()}${text.substring(1)}.';
}

String _count(int n, String one, String many) => n == 1 ? one : '$n $many';

/// A failure of the upload, such as a lost network, in plain words. The
/// message of the core already says what happened and what to do.
String uploadErrorText(UploadException e, String site) => switch (e.code) {
  'key_revoked' => keyRevokedText(site),
  'not_registered' => '${e.message} Register in the settings.',
  _ => e.message,
};

/// Shown when the website admin blocked the key.
String keyRevokedText(String site) =>
    "The website admin blocked this app's key. Uploads to ${siteLabel(site)} "
    'are off.';

/// A character that another key already owns.
String claimedText(String name, String realm) =>
    'Another player already uploaded $name on $realm. Ask the website admin.';

/// A rejected upload: the first 3 problems, in plain words.
String rejectedText(String name, List<UploadProblem> problems) {
  final shown = problems.take(3).map((p) => p.toString()).join('; ');
  final more = problems.length - 3;
  final tail = more <= 0
      ? ''
      : ' And ${_count(more, '1 more problem', 'more problems')}.';
  return 'The website did not accept the data of $name: '
      '${shown.endsWith('.') ? shown : '$shown.'}$tail Fix the saved files, '
      'then upload again.';
}

/// The question before a character leaves the website.
String removeQuestionText(String name, String site) =>
    'Remove $name from ${siteLabel(site)}? The page and its data are deleted.';

/// Shown when a character was removed from the website.
/// It says the rule: a gather never uploads a removed character again, and
/// Upload now sends every removed character again.
String removedText(String name) =>
    '$name was removed from the website. Gathers do not upload it again; '
    'Upload now does.';

/// Shown when Remove is confirmed while an upload or another action runs.
const String busyText =
    'The app is busy with the website. Try again when the upload ends.';

/// Shown when an action failed for a reason that the app did not foresee.
const String genericFailureText =
    'Something went wrong with the website. Try again in a few minutes.';
