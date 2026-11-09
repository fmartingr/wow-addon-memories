/// The English texts of the app, for tests that look for what the user reads.
library;

import 'dart:ui';

import 'package:memories_core/memories_core.dart' show SyncReport;
import 'package:wow_journey/l10n/app_localizations.dart';
import 'package:wow_journey/src/shell/shell_controller.dart';
import 'package:wow_journey/src/ui/messages.dart';
import 'package:wow_journey/src/upload/notice.dart';

final AppLocalizations en = lookupAppLocalizations(const Locale('en'));
final TrayLabels enTray = TrayLabels(en);

String get saveHintText => en.saveHintText;
String get wowFolderGoneText => en.wowFolderGoneText;
String get watchingText => en.watchingText;
String get noDataText => en.noDataText;
String get notAnsweringText => en.notAnswering;
String get cancelLabel => en.cancel;
String get checkSiteLabel => en.checkSiteLabel;
String get registerLabel => en.registerLabel;
String get inviteCodeLabel => en.inviteCodeLabel;
String get websiteAddressLabel => en.websiteAddressLabel;
String get uploadNowLabel => en.uploadNowLabel;
String get uploadingLabel => en.uploadingLabel;
String get requestScreenshotsLabel => en.requestScreenshotsLabel;
String get copyLinkLabel => en.copyLinkLabel;
String get removeFromWebsiteLabel => en.removeFromWebsiteLabel;
String get removeLabel => en.removeLabel;
String get linkCopiedText => en.linkCopiedText;
String get lostKeyText => en.lostKeyText;
String get unlistedText => en.unlistedText;
String get uploadPausedText => en.uploadPausedText;
String get cardUploadOffText => en.cardUploadOff;
String get showWebsiteLabel => en.showWebsiteTab;
String get busyText => en.busyText;
String get genericFailureText => en.genericFailureText;
String get notAMemoriesSiteText => en.notAMemoriesSite;

String noticeEn(Notice n) => noticeText(en, n);
List<String> noticesEn(List<Notice> n) => [for (final x in n) noticeEn(x)];

String keyRevokedText(String site) => en.errKeyRevoked(siteLabel(site));
String claimedText(String name, String realm) => en.errClaimed(name, realm);
String registeredText(String site) => en.registeredText(siteLabel(site));
String notRegisteredText(String site) => en.notRegisteredText(siteLabel(site));
String cardNotRegisteredText(String site) =>
    en.cardNotRegistered(siteLabel(site));
String fingerprintText(String fingerprint) => en.fingerprintText(fingerprint);
String removedText(String name) => en.removedText(name);
String screenshotsLine(String state) => screenshotsText(en, state);
String syncSummary(SyncReport report) => syncSummaryText(en, report);
