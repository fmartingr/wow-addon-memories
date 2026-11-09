/// Turns the codes of the gather, the folder checks and the upload into text
/// in the language of the app.
library;

import 'package:intl/intl.dart';
import 'package:memories_core/memories_core.dart';

import '../../l10n/app_localizations.dart';
import '../settings/settings_store.dart';
import '../upload/notice.dart';

/// A button that a problem offers to fix it.
enum IssueFix {
  chooseWowFolder,
  chooseBackupFolder,
  openLatest,
  tryAgain;

  /// The label of the button.
  String label(AppLocalizations l) => switch (this) {
    chooseWowFolder => l.fixChooseWowFolder,
    chooseBackupFolder => l.fixChooseBackupFolder,
    openLatest => l.fixOpenLatest,
    tryAgain => l.fixTryAgain,
  };
}

/// What happened and what to do, for [code].
String issueText(AppLocalizations l, GatherIssueCode code) => switch (code) {
  GatherIssueCode.noWtf => l.issueNoWtf,
  GatherIssueCode.noData => l.noDataText,
  GatherIssueCode.damagedFile => l.issueDamagedFile,
  GatherIssueCode.accountSkipped => l.issueAccountSkipped,
  GatherIssueCode.characterFailed => l.issueCharacterFailed,
  GatherIssueCode.overlap => l.issueOverlap,
  GatherIssueCode.lockHeld => l.issueLockHeld,
  GatherIssueCode.notWritable => l.issueNotWritable,
  GatherIssueCode.badIndex => l.issueBadIndex,
  GatherIssueCode.badDefault => l.issueBadDefault,
  GatherIssueCode.skippedFile => l.issueSkippedFile,
  GatherIssueCode.duplicateGuid => l.issueDuplicateGuid,
  GatherIssueCode.backupFailed => l.issueBackupFailed,
  GatherIssueCode.screenshotFailed => l.issueScreenshotFailed,
  GatherIssueCode.ioError => l.issueIoError,
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

/// The text of a check of a folder that the user picked.
String flavorCheckText(AppLocalizations l, FlavorCheck check) =>
    switch (check) {
      Valid(:final folder) =>
        folder.hasMemoriesData ? l.flavorReady : l.flavorReadyNoData,
      NoWtf() => l.flavorNoWtf,
      IsInstallFolder(:final flavors) => l.flavorInstallFolder(
        flavors.length,
        flavors.map((f) => f.flavor).join(', '),
      ),
      NotADirectory() => l.flavorNotADirectory,
      NotReadable() => l.flavorNotReadable,
    };

/// The text of a message about the settings file.
String settingsNoticeText(AppLocalizations l, SettingsNotice notice) =>
    switch (notice) {
      SettingsNotice.damaged => l.settingsDamaged,
      SettingsNotice.saveFailed => l.settingsSaveFailed,
    };

/// [bytes] as a short size, such as `12.3 MB`.
String formatSize(AppLocalizations l, int bytes) {
  if (bytes < 1024) return l.sizeBytes(bytes);
  final units = [l.sizeKb, l.sizeMb, l.sizeGb, l.sizeTb];
  var v = bytes / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  final number = NumberFormat('0.0', l.localeName).format(v);
  return units[i](number);
}

/// [t] as `14:32` when it is on the day of [now], else `2026-11-07 14:32`.
/// The digits are the same in every language of the app.
String formatTime(AppLocalizations l, DateTime t, DateTime now) {
  final sameDay =
      t.year == now.year && t.month == now.month && t.day == now.day;
  return DateFormat(
    sameDay ? 'HH:mm' : 'yyyy-MM-dd HH:mm',
    l.localeName,
  ).format(t);
}

/// The game class token [token], such as `HUNTER`, in the language of the
/// app. An unknown token shows capitalized.
String className(AppLocalizations l, String token) {
  final known = switch (token.toUpperCase()) {
    'WARRIOR' => l.classWarrior,
    'PALADIN' => l.classPaladin,
    'HUNTER' => l.classHunter,
    'ROGUE' => l.classRogue,
    'PRIEST' => l.classPriest,
    'DEATHKNIGHT' => l.classDeathKnight,
    'SHAMAN' => l.classShaman,
    'MAGE' => l.classMage,
    'WARLOCK' => l.classWarlock,
    'MONK' => l.classMonk,
    'DRUID' => l.classDruid,
    'DEMONHUNTER' => l.classDemonHunter,
    'EVOKER' => l.classEvoker,
    _ => null,
  };
  if (known != null) return known;
  if (token.isEmpty) return token;
  return token[0].toUpperCase() + token.substring(1).toLowerCase();
}

/// The site as people read it: `example.com`, or `localhost:8080`.
String siteLabel(String site) => _sitePart(site, (uri) => uri.authority);

String _siteHost(String site) => _sitePart(site, (uri) => uri.host);

/// [part] of the parsed [site], or [site] as it is when it does not parse.
String _sitePart(String site, String Function(Uri uri) part) {
  try {
    return part(parseSite(site));
  } on FormatException {
    return site;
  }
}

/// What a successful check of the website shows.
String siteFoundText(AppLocalizations l, SiteInfo info) =>
    info.registration == 'open'
    ? l.siteFoundOpen(info.name)
    : l.siteFoundInvite(info.name);

/// The text of the screenshot state of the key.
String screenshotsText(AppLocalizations l, String state) => switch (state) {
  'pending' => l.screenshotsPending,
  'approved' => l.screenshotsApproved,
  'denied' => l.screenshotsDenied,
  _ => l.screenshotsNone,
};

/// The text under the progress bar of a running upload.
String uploadProgressText(AppLocalizations l, int done, int total) =>
    total <= 0 ? l.uploadingLabel : l.uploadProgress(done, total);

/// The line about the last upload of this run.
String lastUploadText(AppLocalizations l, DateTime? time, DateTime now) =>
    time == null ? l.lastUploadNever : l.lastUpload(formatTime(l, time, now));

/// The result of one upload, in a sentence.
String syncSummaryText(AppLocalizations l, SyncReport report) {
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
    if (sent > 0) l.syncUploaded(sent),
    if (shots > 0) l.syncShots(shots),
    if (sent == 0 && shots == 0 && failed == 0 && shotsFailed == 0)
      l.syncUpToDate,
    if (removed > 0) l.syncRemoved(removed),
    if (failed > 0) l.syncFailed(failed),
    if (shotsFailed > 0) l.syncShotsFailed(shotsFailed),
  ];
  final text = parts.join(', ');
  return '${text[0].toUpperCase()}${text.substring(1)}.';
}

/// A failure of the upload, in plain words. A known code has a text in the
/// language of the app; an unknown code shows the message of the server.
String uploadErrorText(
  AppLocalizations l,
  String code,
  String message,
  String site,
) => switch (code) {
  'network' => l.errNetwork(_siteHost(site)),
  'bad_response' => l.errBadResponse,
  'bad_files' => l.errBadFiles,
  'no_index' => l.errNoIndex,
  'bad_key' => l.errBadKey,
  'bad_site' => _badSiteText(l, site),
  'bad_state' => l.errBadState,
  'failed' => l.errFailed,
  'key_revoked' => l.errKeyRevoked(siteLabel(site)),
  'not_registered' => l.errNotRegistered,
  'invalid' => l.errInvalid,
  'invite_invalid' => l.errInviteInvalid,
  'bad_signature' => l.errBadSignature,
  'rate_limited' => l.errRateLimited,
  'busy' => l.errBusy,
  'quota' => l.errQuota,
  'too_large' => l.errTooLarge,
  'internal' => l.errInternal,
  'bad_request' => l.errBadRequest,
  'not_found' => l.errNotFound,
  'screenshots_not_approved' => l.errScreenshotsNotApproved,
  'unsupported_image' => l.errUnsupportedImage,
  'not_referenced' => l.errNotReferenced,
  'guid_mismatch' => l.errGuidMismatch,
  'gzip_required' => l.errGzipRequired,
  _ when code.startsWith('http_') && int.tryParse(code.substring(5)) != null =>
    l.errHttp(code.substring(5)),
  _ => message,
};

/// Why [site] is refused: `bad_site` is the upload service failing to parse
/// the same address, so parsing it again gives the exact [SiteError].
String _badSiteText(AppLocalizations l, String site) {
  try {
    parseSite(site);
  } on SiteFormatException catch (e) {
    return siteErrorText(l, e.error);
  }
  return l.errBadSite;
}

/// The text of an address that [parseSite] refused.
String siteErrorText(AppLocalizations l, SiteError error) => switch (error) {
  SiteError.invalid => l.siteInvalid,
  SiteError.needsHost => l.siteNeedsHost,
  SiteError.needsHttps => l.siteNeedsHttps,
  SiteError.httpLoopback => l.siteHttpLoopback,
  SiteError.userInfo => l.siteUserInfo,
  SiteError.query => l.siteQuery,
  SiteError.path => l.sitePath,
};

/// The text of [notice] in the language of the app.
String noticeText(AppLocalizations l, Notice notice) => switch (notice) {
  UploadErrorNotice(:final code, :final message, :final site, :final who) =>
    who == null
        ? uploadErrorText(l, code, message, site)
        : l.namedError(who, uploadErrorText(l, code, message, site)),
  ClaimedNotice(:final name, :final realm) => l.errClaimed(
    name,
    realm ?? l.realmUnknown,
  ),
  RejectedNotice(:final name, :final problems, :final more) => l.rejectedText(
    name,
    problems,
    more,
  ),
  TextNotice(:final text) => text,
  SiteAddressNotice(:final error) => siteErrorText(l, error),
  NotAMemoriesSiteNotice() => l.notAMemoriesSite,
  BusyNotice() => l.busyText,
  GenericFailureNotice() => l.genericFailureText,
};
