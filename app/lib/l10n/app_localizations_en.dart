// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'WoW Journey';

  @override
  String get loadingSettings => 'Loading your settings';

  @override
  String get tabOverview => 'Overview';

  @override
  String get tabWebsite => 'Website';

  @override
  String get tabSettings => 'Settings';

  @override
  String get noDataText =>
      'No Memories data yet. Play with the Memories addons on, then log out.';

  @override
  String get wowFolderGoneText =>
      'We cannot find your WoW folder any more. It may have moved, or its drive is not connected. Choose the folder again.';

  @override
  String get saveHintText =>
      'The game saves your journey when you log out or type /reload.';

  @override
  String get watchingText => 'Watching for changes';

  @override
  String get issueNoWtf =>
      'This folder has no WoW game files. Choose the folder of one game version, such as _retail_.';

  @override
  String get issueDamagedFile =>
      'A saved file could not be read, so we skipped it. Log in with that character, log out, then try again.';

  @override
  String get issueAccountSkipped =>
      'The Memories file of an account is missing or damaged, so we skipped its characters. Log in once, log out, then try again.';

  @override
  String get issueCharacterFailed =>
      'We could not update the data of one character, so we left it as it was. Check its folder in the latest data, then try again.';

  @override
  String get issueOverlap =>
      'The backup folder is inside the game files. Choose a backup folder outside the World of Warcraft folder.';

  @override
  String get issueLockHeld =>
      'Another gather is running on this backup folder. Wait until it ends, then try again.';

  @override
  String get issueNotWritable =>
      'We cannot write to the backup folder. Check that its drive is connected and has free space, or choose another backup folder.';

  @override
  String get issueBadIndex =>
      'The file index.json in the latest data is damaged. Move it out of the folder, then try again.';

  @override
  String get issueBadDefault =>
      'The first character to show is not in your data. Try again.';

  @override
  String get issueSkippedFile =>
      'A saved file had no Memories data or belonged to another character, so we skipped it.';

  @override
  String get issueDuplicateGuid =>
      'Two folders hold the same character. We kept the one you played last.';

  @override
  String get issueBackupFailed =>
      'We could not copy a saved file into the backup folder. Check that its drive has free space, then try again.';

  @override
  String get issueScreenshotFailed =>
      'We could not copy a screenshot. Check that the drive has free space, then try again.';

  @override
  String get issueIoError =>
      'A file could not be read or written, so the gather stopped. Check that your drives are connected and have free space, then try again.';

  @override
  String get fixChooseWowFolder => 'Choose folder';

  @override
  String get fixChooseBackupFolder => 'Choose backup folder';

  @override
  String get fixOpenLatest => 'Open latest data';

  @override
  String get fixTryAgain => 'Try again';

  @override
  String get statusGathering => 'Gathering your journey…';

  @override
  String get statusFailed =>
      'The last gather did not finish. See the problem below.';

  @override
  String statusDoneProblems(String when) {
    return 'Gathered with problems. Last gathered $when';
  }

  @override
  String statusDone(String when) {
    return 'Up to date. Last gathered $when';
  }

  @override
  String statusIdleLast(String when) {
    return 'Last gathered $when';
  }

  @override
  String get statusNever => 'Never gathered';

  @override
  String statusSemantics(String status) {
    return 'Status: $status';
  }

  @override
  String get gathering => 'Gathering…';

  @override
  String get gatheringSemantics => 'Gathering, please wait';

  @override
  String get gatheringProgress => 'Gathering';

  @override
  String get gatherNow => 'Gather now';

  @override
  String get countCharacters => 'Characters';

  @override
  String get countJournalLines => 'Journal lines';

  @override
  String get countScreenshots => 'Screenshots';

  @override
  String countSemantics(String label, int value) {
    return '$label: $value';
  }

  @override
  String get charactersTitle => 'Characters';

  @override
  String get noCharacters => 'No characters yet. Click Gather now.';

  @override
  String characterLevel(int level) {
    return 'Level $level';
  }

  @override
  String get backupFolderTitle => 'Backup folder';

  @override
  String get notSet => 'Not set';

  @override
  String backupSize(String size) {
    return 'Size: $size';
  }

  @override
  String get openBackupFolder => 'Open backup folder';

  @override
  String get openLatestData => 'Open latest data';

  @override
  String get openFolderFailed =>
      'We could not open this folder. If you have not gathered yet, click Gather now first.';

  @override
  String get dismiss => 'Dismiss';

  @override
  String get showWebsiteTab => 'Show the Website tab';

  @override
  String andMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'and $count more',
      one: 'and 1 more',
    );
    return '$_temp0';
  }

  @override
  String sizeBytes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bytes',
    );
    return '$_temp0';
  }

  @override
  String sizeKb(String value) {
    return '$value KB';
  }

  @override
  String sizeMb(String value) {
    return '$value MB';
  }

  @override
  String sizeGb(String value) {
    return '$value GB';
  }

  @override
  String sizeTb(String value) {
    return '$value TB';
  }

  @override
  String get classWarrior => 'Warrior';

  @override
  String get classPaladin => 'Paladin';

  @override
  String get classHunter => 'Hunter';

  @override
  String get classRogue => 'Rogue';

  @override
  String get classPriest => 'Priest';

  @override
  String get classDeathKnight => 'Death Knight';

  @override
  String get classShaman => 'Shaman';

  @override
  String get classMage => 'Mage';

  @override
  String get classWarlock => 'Warlock';

  @override
  String get classMonk => 'Monk';

  @override
  String get classDruid => 'Druid';

  @override
  String get classDemonHunter => 'Demon Hunter';

  @override
  String get classEvoker => 'Evoker';

  @override
  String get settingsSaveFailed =>
      'We could not save your settings. Check that your disk has free space, then change the setting again.';

  @override
  String get settingsDamaged =>
      'Your settings file was damaged, so the app started with the default settings. Check your folders and switches.';

  @override
  String get wowFolderTitle => 'WoW folder';

  @override
  String get changeWowFolderSemantics => 'Change the WoW folder';

  @override
  String get changeBackupFolderSemantics => 'Change the backup folder';

  @override
  String get change => 'Change';

  @override
  String get watchTitle => 'Watch';

  @override
  String get watchSubtitle => 'Gather on its own each time the game saves.';

  @override
  String get startAtLoginTitle => 'Start at login';

  @override
  String get startAtLoginSubtitle => 'Start the app hidden when you sign in.';

  @override
  String get languageTitle => 'Language';

  @override
  String get languageSystem => 'System';

  @override
  String get versionTitle => 'Version';

  @override
  String versionText(String version, String core) {
    return 'WoW Journey $version, $core';
  }

  @override
  String get wizardTitle => 'Welcome to WoW Journey';

  @override
  String wizardStep(int step, int total) {
    return 'Step $step of $total';
  }

  @override
  String get back => 'Back';

  @override
  String backSemantics(int step) {
    return 'Back to step $step';
  }

  @override
  String get next => 'Next';

  @override
  String get nextSemantics => 'Next step';

  @override
  String get finish => 'Finish';

  @override
  String get finishSemantics => 'Finish the setup';

  @override
  String get wowStepTitle => 'Your WoW folder';

  @override
  String get wowStepIntro =>
      'We read the files that the Memories addons save in this folder. We never change them.';

  @override
  String get lookingForWow => 'Looking for World of Warcraft…';

  @override
  String get noWowFound =>
      'We could not find World of Warcraft. Choose the folder of one game version, such as _retail_, inside your World of Warcraft folder.';

  @override
  String get chooseFolder => 'Choose folder';

  @override
  String get chooseWowSemantics => 'Choose the WoW folder';

  @override
  String get noMemoriesYet => 'No Memories data yet.';

  @override
  String wowFolderSemantics(String path) {
    return 'WoW folder: $path';
  }

  @override
  String get backupStepTitle => 'Your backup folder';

  @override
  String get backupStepIntro =>
      'We keep a copy of your game files and your screenshots here.';

  @override
  String backupFolderSemantics(String path) {
    return 'Backup folder: $path';
  }

  @override
  String get backupFolderSemanticsNotSet => 'Backup folder: not set';

  @override
  String get chooseBackupPrompt => 'Choose a backup folder.';

  @override
  String get switchStepTitle => 'How the app runs';

  @override
  String get switchStepIntro => 'You can change these later in Settings.';

  @override
  String get useThisFolder => 'Use this folder';

  @override
  String get pickerFailed =>
      'We could not open the folder picker. Try again, or restart the app.';

  @override
  String get checkFailed =>
      'We could not check this folder. Try again, or choose another folder.';

  @override
  String get chooseGameVersion => 'Choose a game version';

  @override
  String get backupInsideWow =>
      'This folder is inside your World of Warcraft folder, or holds it. Choose a backup folder outside the game folder.';

  @override
  String get backupInsideWowFirst =>
      'Your backup folder is inside this World of Warcraft folder, or holds it. Choose another backup folder first, then this WoW folder.';

  @override
  String get useBackupTitle => 'Use this backup folder?';

  @override
  String useBackupBody(String path) {
    return 'New gathers go to $path. Your old backup folder stays as it is. We do not move or delete it.';
  }

  @override
  String get cancel => 'Cancel';

  @override
  String get flavorReady => 'This WoW folder is ready.';

  @override
  String get flavorReadyNoData =>
      'This WoW folder is ready, but it has no Memories data yet. Play with the Memories addons on. The game saves its files when you log out or type /reload.';

  @override
  String get flavorNoWtf =>
      'This folder is not a WoW game folder. It has no WTF/Account folder. Pick the folder of one game version inside your World of Warcraft folder, such as _retail_.';

  @override
  String flavorInstallFolder(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'This is the World of Warcraft folder. It holds $count game versions: $names. Pick one of them.',
      one:
          'This is the World of Warcraft folder. It holds one game version: $names. Pick that folder.',
    );
    return '$_temp0';
  }

  @override
  String get flavorNotADirectory =>
      'This is not a folder, or it does not exist any more. Pick a folder.';

  @override
  String get flavorNotReadable =>
      'This folder, or a folder in it, cannot be read. Check that your user may open it, then pick it again.';

  @override
  String get websiteTitle => 'Website';

  @override
  String websiteCardTitle(String site) {
    return 'Website: $site';
  }

  @override
  String get registrationTitle => 'Registration';

  @override
  String get unlistedText =>
      'Your character pages are unlisted: anybody with the link can open them.';

  @override
  String get lostKeyText =>
      'If you reinstall the app, ask the website admin to move your characters to your new key.';

  @override
  String get websiteAddressLabel => 'Website address';

  @override
  String get checkSiteLabel => 'Check';

  @override
  String get inviteCodeLabel => 'Invite code';

  @override
  String get registerLabel => 'Register';

  @override
  String get uploadSwitchTitle => 'Upload';

  @override
  String get uploadSwitchSubtitle =>
      'Send your journey to the website after each gather.';

  @override
  String get uploadNowLabel => 'Upload now';

  @override
  String get uploadingLabel => 'Uploading…';

  @override
  String get uploadingSemantics => 'Uploading, please wait';

  @override
  String get uploadPausedText =>
      'Upload paused. It continues after the next gather.';

  @override
  String get requestScreenshotsLabel => 'Request screenshots';

  @override
  String get copyLinkLabel => 'Copy link';

  @override
  String copyLinkSemantics(String name) {
    return 'Copy link of $name';
  }

  @override
  String get removeFromWebsiteLabel => 'Remove from website';

  @override
  String removeFromWebsiteSemantics(String name) {
    return 'Remove $name from website';
  }

  @override
  String get linkCopiedText => 'Link copied';

  @override
  String get removeLabel => 'Remove';

  @override
  String siteFoundOpen(String name) {
    return 'Found $name. Anybody can register here.';
  }

  @override
  String siteFoundInvite(String name) {
    return 'Found $name. You need an invite code from the website admin to register.';
  }

  @override
  String get notAMemoriesSite =>
      'This address does not look like a Memories website. Check the address.';

  @override
  String registeredText(String site) {
    return 'Registered on $site.';
  }

  @override
  String notRegisteredText(String site) {
    return 'Not registered on $site. Register to upload your journey.';
  }

  @override
  String fingerprintText(String fingerprint) {
    return 'Your key: $fingerprint';
  }

  @override
  String get screenshotsNone =>
      'Screenshots are not uploaded. Ask the website admin to approve them.';

  @override
  String get screenshotsPending =>
      'Waiting for the website admin to approve your screenshots.';

  @override
  String get screenshotsApproved =>
      'Your screenshots are uploaded with your journey.';

  @override
  String get screenshotsDenied =>
      'The website admin did not approve screenshots. You can ask again.';

  @override
  String cardNotRegistered(String site) {
    return 'You are not registered on $site. Register below to share your journey.';
  }

  @override
  String get cardUploadOff =>
      'Upload is off. Turn on the Upload switch below to send your journey.';

  @override
  String uploadProgress(int done, int total) {
    return 'Uploading $done of $total';
  }

  @override
  String get lastUploadNever => 'Nothing uploaded yet.';

  @override
  String lastUpload(String time) {
    return 'Last upload $time';
  }

  @override
  String syncUploaded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'uploaded $count characters',
      one: 'uploaded 1 character',
    );
    return '$_temp0';
  }

  @override
  String syncShots(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'sent $count screenshots',
      one: 'sent 1 screenshot',
    );
    return '$_temp0';
  }

  @override
  String get syncUpToDate => 'everything is up to date';

  @override
  String syncRemoved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'skipped $count removed characters (Upload now sends them again)',
      one: 'skipped 1 removed character (Upload now sends it again)',
    );
    return '$_temp0';
  }

  @override
  String syncFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count characters failed',
      one: '1 character failed',
    );
    return '$_temp0';
  }

  @override
  String syncShotsFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count screenshots failed',
      one: '1 screenshot failed',
    );
    return '$_temp0';
  }

  @override
  String errNetwork(String host) {
    return 'Could not reach $host. Check the internet connection and the website address.';
  }

  @override
  String get errBadResponse =>
      'The website sent an answer that this program does not understand. Check the website address.';

  @override
  String get errBadFiles =>
      'A file of your journey is missing or cannot be read, so it was not uploaded. Gather again, then try again.';

  @override
  String get errNoIndex =>
      'Could not read index.json of the latest data. Run the gather first, then try again.';

  @override
  String get errBadKey =>
      'The key file of the app cannot be read or written. Check its permissions and the free space of its folder.';

  @override
  String get errBadSite =>
      'The website address is not valid. Write it like https://example.com.';

  @override
  String get errBadState =>
      'The character was removed from the website, but the app could not save that, so the next gather may upload it again. Check that the app folder can be written to.';

  @override
  String get errFailed =>
      'The upload stopped because of a problem inside the app. Try again after the next gather.';

  @override
  String errHttp(String status) {
    return 'The website answered with status $status. Try again later, and check the website address.';
  }

  @override
  String errKeyRevoked(String site) {
    return 'The website admin blocked this app\'s key. Uploads to $site are off.';
  }

  @override
  String get errNotRegistered =>
      'The website does not know the key of this app yet. Register in the settings.';

  @override
  String errClaimed(String name, String realm) {
    return 'Another player already uploaded $name on $realm. Ask the website admin.';
  }

  @override
  String get realmUnknown => 'its realm';

  @override
  String get errInvalid =>
      'The website did not accept the data. Fix the saved files, then upload again.';

  @override
  String get errInviteInvalid =>
      'The invite code is not valid. Ask the website admin for a new one.';

  @override
  String get errBadSignature =>
      'The website did not accept the signature of the app. Check that the clock of your computer is right, then try again.';

  @override
  String get errRateLimited =>
      'Too many requests. Wait a minute, then try again.';

  @override
  String get errBusy =>
      'The website is busy with other uploads. Try again in a few minutes.';

  @override
  String get errQuota =>
      'The website has no more room for your data. Ask the website admin.';

  @override
  String get errTooLarge =>
      'Your data is too large for this website. Ask the website admin to raise the limit.';

  @override
  String get errInternal =>
      'The website had a problem. Try again in a few minutes.';

  @override
  String get errBadRequest =>
      'The website could not read the request. Try again, and update the app if it keeps happening.';

  @override
  String get errNotFound => 'This website has no such character for this key.';

  @override
  String get errScreenshotsNotApproved =>
      'The website admin has not approved your screenshots yet.';

  @override
  String get errUnsupportedImage =>
      'The website did not accept a screenshot because its image type is not supported.';

  @override
  String get errNotReferenced =>
      'A screenshot does not belong to any journal line, so the website did not keep it.';

  @override
  String get errGuidMismatch =>
      'This character name already belongs to another character on the website. Ask the website admin.';

  @override
  String get errGzipRequired =>
      'The upload was not compressed as the website needs. Update the app, then try again.';

  @override
  String namedError(String name, String text) {
    return '$name: $text';
  }

  @override
  String rejectedText(String name, String problems, int more) {
    String _temp0 = intl.Intl.pluralLogic(
      more,
      locale: localeName,
      other: ' And $more more problems.',
      one: ' And 1 more problem.',
      zero: '',
    );
    return 'The website did not accept the data of $name: $problems$_temp0 Fix the saved files, then upload again.';
  }

  @override
  String get siteInvalid =>
      'The website address is not valid. Write it like https://example.com.';

  @override
  String get siteNeedsHost =>
      'The website address needs a scheme and a host, like https://example.com.';

  @override
  String get siteNeedsHttps => 'The website address must start with https://.';

  @override
  String get siteHttpLoopback =>
      'The website address must start with https://. Plain http:// is only allowed for localhost, 127.0.0.1 and [::1].';

  @override
  String get siteUserInfo =>
      'The website address may not hold a user name or a password.';

  @override
  String get siteQuery =>
      'The website address may not hold a query or a fragment.';

  @override
  String get sitePath =>
      'The website address may not hold a path. Use the address of the site itself, like https://example.com.';

  @override
  String removeQuestionText(String name, String site) {
    return 'Remove $name from $site? The page and its data are deleted.';
  }

  @override
  String removedText(String name) {
    return '$name was removed from the website. Gathers do not upload it again; Upload now does.';
  }

  @override
  String get busyText =>
      'The app is busy with the website. Try again when the upload ends.';

  @override
  String get genericFailureText =>
      'Something went wrong with the website. Try again in a few minutes.';

  @override
  String get notAnswering =>
      'WoW Journey is already running, but it did not answer. Quit it from its tray icon menu, or end it in the task manager, then start it again.';

  @override
  String get close => 'Close';

  @override
  String get trayGatherNow => 'Gather now';

  @override
  String get trayOpenWindow => 'Open window';

  @override
  String get trayOpenBackupFolder => 'Open backup folder';

  @override
  String get trayQuit => 'Quit';
}
