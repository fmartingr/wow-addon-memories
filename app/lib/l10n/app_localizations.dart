import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_it.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('it'),
    Locale('pt'),
  ];

  /// The name of the app. Not translated.
  ///
  /// In en, this message translates to:
  /// **'WoW Journey'**
  String get appTitle;

  /// Screen reader label of the spinner while the settings load.
  ///
  /// In en, this message translates to:
  /// **'Loading your settings'**
  String get loadingSettings;

  /// Name of the first tab.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get tabOverview;

  /// Name of the second tab.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get tabWebsite;

  /// Name of the third tab.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get tabSettings;

  /// Shown when the gather found no character with Memories data.
  ///
  /// In en, this message translates to:
  /// **'No Memories data yet. Play with the Memories addons on, then log out.'**
  String get noDataText;

  /// Shown when the saved WoW folder is gone.
  ///
  /// In en, this message translates to:
  /// **'We cannot find your WoW folder any more. It may have moved, or its drive is not connected. Choose the folder again.'**
  String get wowFolderGoneText;

  /// Hint about when the game writes its files. /reload is a game command and stays as is.
  ///
  /// In en, this message translates to:
  /// **'The game saves your journey when you log out or type /reload.'**
  String get saveHintText;

  /// Tag shown while Watch is on.
  ///
  /// In en, this message translates to:
  /// **'Watching for changes'**
  String get watchingText;

  /// Gather problem: the folder has no WTF folder. _retail_ is a folder name.
  ///
  /// In en, this message translates to:
  /// **'This folder has no WoW game files. Choose the folder of one game version, such as _retail_.'**
  String get issueNoWtf;

  /// Gather problem: a saved file is damaged.
  ///
  /// In en, this message translates to:
  /// **'A saved file could not be read, so we skipped it. Log in with that character, log out, then try again.'**
  String get issueDamagedFile;

  /// Gather problem: the Memories file of an account is missing or damaged.
  ///
  /// In en, this message translates to:
  /// **'The Memories file of an account is missing or damaged, so we skipped its characters. Log in once, log out, then try again.'**
  String get issueAccountSkipped;

  /// Gather problem: one character could not be updated.
  ///
  /// In en, this message translates to:
  /// **'We could not update the data of one character, so we left it as it was. Check its folder in the latest data, then try again.'**
  String get issueCharacterFailed;

  /// Gather problem: the backup folder is inside the game folder.
  ///
  /// In en, this message translates to:
  /// **'The backup folder is inside the game files. Choose a backup folder outside the World of Warcraft folder.'**
  String get issueOverlap;

  /// Gather problem: another gather holds the lock.
  ///
  /// In en, this message translates to:
  /// **'Another gather is running on this backup folder. Wait until it ends, then try again.'**
  String get issueLockHeld;

  /// Gather problem: the backup folder cannot be written.
  ///
  /// In en, this message translates to:
  /// **'We cannot write to the backup folder. Check that its drive is connected and has free space, or choose another backup folder.'**
  String get issueNotWritable;

  /// Gather problem: index.json is damaged. index.json is a file name.
  ///
  /// In en, this message translates to:
  /// **'The file index.json in the latest data is damaged. Move it out of the folder, then try again.'**
  String get issueBadIndex;

  /// Gather problem: the default character is not in the data.
  ///
  /// In en, this message translates to:
  /// **'The first character to show is not in your data. Try again.'**
  String get issueBadDefault;

  /// Gather note: a file was skipped.
  ///
  /// In en, this message translates to:
  /// **'A saved file had no Memories data or belonged to another character, so we skipped it.'**
  String get issueSkippedFile;

  /// Gather note: two folders hold the same character.
  ///
  /// In en, this message translates to:
  /// **'Two folders hold the same character. We kept the one you played last.'**
  String get issueDuplicateGuid;

  /// Gather problem: a file could not be backed up.
  ///
  /// In en, this message translates to:
  /// **'We could not copy a saved file into the backup folder. Check that its drive has free space, then try again.'**
  String get issueBackupFailed;

  /// Gather problem: a screenshot could not be copied.
  ///
  /// In en, this message translates to:
  /// **'We could not copy a screenshot. Check that the drive has free space, then try again.'**
  String get issueScreenshotFailed;

  /// Gather problem: a file error stopped the gather.
  ///
  /// In en, this message translates to:
  /// **'A file could not be read or written, so the gather stopped. Check that your drives are connected and have free space, then try again.'**
  String get issueIoError;

  /// Button that picks the WoW folder again.
  ///
  /// In en, this message translates to:
  /// **'Choose folder'**
  String get fixChooseWowFolder;

  /// Button that picks the backup folder again.
  ///
  /// In en, this message translates to:
  /// **'Choose backup folder'**
  String get fixChooseBackupFolder;

  /// Button that opens the latest data folder.
  ///
  /// In en, this message translates to:
  /// **'Open latest data'**
  String get fixOpenLatest;

  /// Button that runs the gather again.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get fixTryAgain;

  /// Status line while a gather runs.
  ///
  /// In en, this message translates to:
  /// **'Gathering your journey…'**
  String get statusGathering;

  /// Status line after a failed gather.
  ///
  /// In en, this message translates to:
  /// **'The last gather did not finish. See the problem below.'**
  String get statusFailed;

  /// Status line after a gather with problems. {when} is a time.
  ///
  /// In en, this message translates to:
  /// **'Gathered with problems. Last gathered {when}'**
  String statusDoneProblems(String when);

  /// Status line after a good gather. {when} is a time.
  ///
  /// In en, this message translates to:
  /// **'Up to date. Last gathered {when}'**
  String statusDone(String when);

  /// Status line at rest after an earlier gather. {when} is a time.
  ///
  /// In en, this message translates to:
  /// **'Last gathered {when}'**
  String statusIdleLast(String when);

  /// Status line before the first gather.
  ///
  /// In en, this message translates to:
  /// **'Never gathered'**
  String get statusNever;

  /// Screen reader label of the status line.
  ///
  /// In en, this message translates to:
  /// **'Status: {status}'**
  String statusSemantics(String status);

  /// Label of the Gather button while a gather runs.
  ///
  /// In en, this message translates to:
  /// **'Gathering…'**
  String get gathering;

  /// Screen reader label of the Gather button while a gather runs.
  ///
  /// In en, this message translates to:
  /// **'Gathering, please wait'**
  String get gatheringSemantics;

  /// Screen reader label of the gather progress bar.
  ///
  /// In en, this message translates to:
  /// **'Gathering'**
  String get gatheringProgress;

  /// Label of the Gather button.
  ///
  /// In en, this message translates to:
  /// **'Gather now'**
  String get gatherNow;

  /// Label of the count of characters.
  ///
  /// In en, this message translates to:
  /// **'Characters'**
  String get countCharacters;

  /// Label of the count of journal lines.
  ///
  /// In en, this message translates to:
  /// **'Journal lines'**
  String get countJournalLines;

  /// Label of the count of screenshots.
  ///
  /// In en, this message translates to:
  /// **'Screenshots'**
  String get countScreenshots;

  /// Screen reader label of a count.
  ///
  /// In en, this message translates to:
  /// **'{label}: {value}'**
  String countSemantics(String label, int value);

  /// Title of the list of characters.
  ///
  /// In en, this message translates to:
  /// **'Characters'**
  String get charactersTitle;

  /// Shown when the list of characters is empty.
  ///
  /// In en, this message translates to:
  /// **'No characters yet. Click Gather now.'**
  String get noCharacters;

  /// The level of a character.
  ///
  /// In en, this message translates to:
  /// **'Level {level}'**
  String characterLevel(int level);

  /// Title of the backup folder card and row.
  ///
  /// In en, this message translates to:
  /// **'Backup folder'**
  String get backupFolderTitle;

  /// Shown when a folder is not set.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get notSet;

  /// The size of the backup folder. {size} is a size such as 1.5 MB.
  ///
  /// In en, this message translates to:
  /// **'Size: {size}'**
  String backupSize(String size);

  /// Button that opens the backup folder.
  ///
  /// In en, this message translates to:
  /// **'Open backup folder'**
  String get openBackupFolder;

  /// Button that opens the latest data folder.
  ///
  /// In en, this message translates to:
  /// **'Open latest data'**
  String get openLatestData;

  /// Shown when a folder cannot be opened.
  ///
  /// In en, this message translates to:
  /// **'We could not open this folder. If you have not gathered yet, click Gather now first.'**
  String get openFolderFailed;

  /// Tooltip of the button that closes a notice.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get dismiss;

  /// Button of an upload problem that opens the Website tab.
  ///
  /// In en, this message translates to:
  /// **'Show the Website tab'**
  String get showWebsiteTab;

  /// After 3 listed files: how many more there are.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{and 1 more} other{and {count} more}}'**
  String andMore(int count);

  /// A size below 1 KB.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{{count} bytes}}'**
  String sizeBytes(int count);

  /// A size in kilobytes. {value} is a formatted number.
  ///
  /// In en, this message translates to:
  /// **'{value} KB'**
  String sizeKb(String value);

  /// A size in megabytes. {value} is a formatted number.
  ///
  /// In en, this message translates to:
  /// **'{value} MB'**
  String sizeMb(String value);

  /// A size in gigabytes. {value} is a formatted number.
  ///
  /// In en, this message translates to:
  /// **'{value} GB'**
  String sizeGb(String value);

  /// A size in terabytes. {value} is a formatted number.
  ///
  /// In en, this message translates to:
  /// **'{value} TB'**
  String sizeTb(String value);

  /// Name of the game class Warrior.
  ///
  /// In en, this message translates to:
  /// **'Warrior'**
  String get classWarrior;

  /// Name of the game class Paladin.
  ///
  /// In en, this message translates to:
  /// **'Paladin'**
  String get classPaladin;

  /// Name of the game class Hunter.
  ///
  /// In en, this message translates to:
  /// **'Hunter'**
  String get classHunter;

  /// Name of the game class Rogue.
  ///
  /// In en, this message translates to:
  /// **'Rogue'**
  String get classRogue;

  /// Name of the game class Priest.
  ///
  /// In en, this message translates to:
  /// **'Priest'**
  String get classPriest;

  /// Name of the game class Death Knight.
  ///
  /// In en, this message translates to:
  /// **'Death Knight'**
  String get classDeathKnight;

  /// Name of the game class Shaman.
  ///
  /// In en, this message translates to:
  /// **'Shaman'**
  String get classShaman;

  /// Name of the game class Mage.
  ///
  /// In en, this message translates to:
  /// **'Mage'**
  String get classMage;

  /// Name of the game class Warlock.
  ///
  /// In en, this message translates to:
  /// **'Warlock'**
  String get classWarlock;

  /// Name of the game class Monk.
  ///
  /// In en, this message translates to:
  /// **'Monk'**
  String get classMonk;

  /// Name of the game class Druid.
  ///
  /// In en, this message translates to:
  /// **'Druid'**
  String get classDruid;

  /// Name of the game class Demon Hunter.
  ///
  /// In en, this message translates to:
  /// **'Demon Hunter'**
  String get classDemonHunter;

  /// Name of the game class Evoker.
  ///
  /// In en, this message translates to:
  /// **'Evoker'**
  String get classEvoker;

  /// Shown when the settings file cannot be written.
  ///
  /// In en, this message translates to:
  /// **'We could not save your settings. Check that your disk has free space, then change the setting again.'**
  String get settingsSaveFailed;

  /// Shown when the settings file cannot be read.
  ///
  /// In en, this message translates to:
  /// **'Your settings file was damaged, so the app started with the default settings. Check your folders and switches.'**
  String get settingsDamaged;

  /// Title of the WoW folder row.
  ///
  /// In en, this message translates to:
  /// **'WoW folder'**
  String get wowFolderTitle;

  /// Screen reader label of the Change button of the WoW folder.
  ///
  /// In en, this message translates to:
  /// **'Change the WoW folder'**
  String get changeWowFolderSemantics;

  /// Screen reader label of the Change button of the backup folder.
  ///
  /// In en, this message translates to:
  /// **'Change the backup folder'**
  String get changeBackupFolderSemantics;

  /// Label of a button that changes a folder.
  ///
  /// In en, this message translates to:
  /// **'Change'**
  String get change;

  /// Title of the Watch switch.
  ///
  /// In en, this message translates to:
  /// **'Watch'**
  String get watchTitle;

  /// Subtitle of the Watch switch.
  ///
  /// In en, this message translates to:
  /// **'Gather on its own each time the game saves.'**
  String get watchSubtitle;

  /// Title of the Start at login switch.
  ///
  /// In en, this message translates to:
  /// **'Start at login'**
  String get startAtLoginTitle;

  /// Subtitle of the Start at login switch.
  ///
  /// In en, this message translates to:
  /// **'Start the app hidden when you sign in.'**
  String get startAtLoginSubtitle;

  /// Title of the Language row of the settings.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get languageTitle;

  /// Choice of the Language row that follows the language of the operating system.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get languageSystem;

  /// Title of the Version row.
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get versionTitle;

  /// The versions of the app and of its core. {core} is a technical text.
  ///
  /// In en, this message translates to:
  /// **'WoW Journey {version}, {core}'**
  String versionText(String version, String core);

  /// Title of the first-run wizard.
  ///
  /// In en, this message translates to:
  /// **'Welcome to WoW Journey'**
  String get wizardTitle;

  /// Step counter of the wizard.
  ///
  /// In en, this message translates to:
  /// **'Step {step} of {total}'**
  String wizardStep(int step, int total);

  /// Label of the Back button of the wizard.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// Screen reader label of the Back button.
  ///
  /// In en, this message translates to:
  /// **'Back to step {step}'**
  String backSemantics(int step);

  /// Label of the Next button of the wizard.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get next;

  /// Screen reader label of the Next button.
  ///
  /// In en, this message translates to:
  /// **'Next step'**
  String get nextSemantics;

  /// Label of the last button of the wizard.
  ///
  /// In en, this message translates to:
  /// **'Finish'**
  String get finish;

  /// Screen reader label of the Finish button.
  ///
  /// In en, this message translates to:
  /// **'Finish the setup'**
  String get finishSemantics;

  /// Title of step 1 of the wizard.
  ///
  /// In en, this message translates to:
  /// **'Your WoW folder'**
  String get wowStepTitle;

  /// Intro of step 1 of the wizard.
  ///
  /// In en, this message translates to:
  /// **'We read the files that the Memories addons save in this folder. We never change them.'**
  String get wowStepIntro;

  /// Shown while the app looks for the game folder.
  ///
  /// In en, this message translates to:
  /// **'Looking for World of Warcraft…'**
  String get lookingForWow;

  /// Shown when no game folder was found. _retail_ is a folder name.
  ///
  /// In en, this message translates to:
  /// **'We could not find World of Warcraft. Choose the folder of one game version, such as _retail_, inside your World of Warcraft folder.'**
  String get noWowFound;

  /// Label of the button that picks the WoW folder.
  ///
  /// In en, this message translates to:
  /// **'Choose folder'**
  String get chooseFolder;

  /// Screen reader label of the Choose folder button.
  ///
  /// In en, this message translates to:
  /// **'Choose the WoW folder'**
  String get chooseWowSemantics;

  /// Detail of a game folder that has no Memories data.
  ///
  /// In en, this message translates to:
  /// **'No Memories data yet.'**
  String get noMemoriesYet;

  /// Screen reader label of the chosen WoW folder.
  ///
  /// In en, this message translates to:
  /// **'WoW folder: {path}'**
  String wowFolderSemantics(String path);

  /// Title of step 2 of the wizard.
  ///
  /// In en, this message translates to:
  /// **'Your backup folder'**
  String get backupStepTitle;

  /// Intro of step 2 of the wizard.
  ///
  /// In en, this message translates to:
  /// **'We keep a copy of your game files and your screenshots here.'**
  String get backupStepIntro;

  /// Screen reader label of the chosen backup folder.
  ///
  /// In en, this message translates to:
  /// **'Backup folder: {path}'**
  String backupFolderSemantics(String path);

  /// Screen reader label when no backup folder is chosen.
  ///
  /// In en, this message translates to:
  /// **'Backup folder: not set'**
  String get backupFolderSemanticsNotSet;

  /// Shown when no backup folder is chosen.
  ///
  /// In en, this message translates to:
  /// **'Choose a backup folder.'**
  String get chooseBackupPrompt;

  /// Title of step 3 of the wizard.
  ///
  /// In en, this message translates to:
  /// **'How the app runs'**
  String get switchStepTitle;

  /// Intro of step 3 of the wizard.
  ///
  /// In en, this message translates to:
  /// **'You can change these later in Settings.'**
  String get switchStepIntro;

  /// Label of the confirm button of the folder picker and of a dialog.
  ///
  /// In en, this message translates to:
  /// **'Use this folder'**
  String get useThisFolder;

  /// Shown when the folder picker fails to open.
  ///
  /// In en, this message translates to:
  /// **'We could not open the folder picker. Try again, or restart the app.'**
  String get pickerFailed;

  /// Shown when the check of a picked folder fails.
  ///
  /// In en, this message translates to:
  /// **'We could not check this folder. Try again, or choose another folder.'**
  String get checkFailed;

  /// Title of the dialog that asks for one game version.
  ///
  /// In en, this message translates to:
  /// **'Choose a game version'**
  String get chooseGameVersion;

  /// Shown when the backup folder overlaps the game folder.
  ///
  /// In en, this message translates to:
  /// **'This folder is inside your World of Warcraft folder, or holds it. Choose a backup folder outside the game folder.'**
  String get backupInsideWow;

  /// Shown when a new WoW folder overlaps the backup folder.
  ///
  /// In en, this message translates to:
  /// **'Your backup folder is inside this World of Warcraft folder, or holds it. Choose another backup folder first, then this WoW folder.'**
  String get backupInsideWowFirst;

  /// Title of the dialog that confirms a new backup folder.
  ///
  /// In en, this message translates to:
  /// **'Use this backup folder?'**
  String get useBackupTitle;

  /// Body of the dialog that confirms a new backup folder.
  ///
  /// In en, this message translates to:
  /// **'New gathers go to {path}. Your old backup folder stays as it is. We do not move or delete it.'**
  String useBackupBody(String path);

  /// Label of a button that closes a dialog with no change.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// Folder check: the folder is ready.
  ///
  /// In en, this message translates to:
  /// **'This WoW folder is ready.'**
  String get flavorReady;

  /// Folder check: the folder is ready but has no Memories data. /reload is a game command.
  ///
  /// In en, this message translates to:
  /// **'This WoW folder is ready, but it has no Memories data yet. Play with the Memories addons on. The game saves its files when you log out or type /reload.'**
  String get flavorReadyNoData;

  /// Folder check: the folder is not a game folder. WTF/Account and _retail_ are folder names.
  ///
  /// In en, this message translates to:
  /// **'This folder is not a WoW game folder. It has no WTF/Account folder. Pick the folder of one game version inside your World of Warcraft folder, such as _retail_.'**
  String get flavorNoWtf;

  /// Folder check: the folder is the install folder. {names} lists the game versions.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{This is the World of Warcraft folder. It holds one game version: {names}. Pick that folder.} other{This is the World of Warcraft folder. It holds {count} game versions: {names}. Pick one of them.}}'**
  String flavorInstallFolder(int count, String names);

  /// Folder check: the path is not a folder.
  ///
  /// In en, this message translates to:
  /// **'This is not a folder, or it does not exist any more. Pick a folder.'**
  String get flavorNotADirectory;

  /// Folder check: the folder cannot be read.
  ///
  /// In en, this message translates to:
  /// **'This folder, or a folder in it, cannot be read. Check that your user may open it, then pick it again.'**
  String get flavorNotReadable;

  /// Title of the Website section.
  ///
  /// In en, this message translates to:
  /// **'Website'**
  String get websiteTitle;

  /// Title of the Website card. {site} is a web address.
  ///
  /// In en, this message translates to:
  /// **'Website: {site}'**
  String websiteCardTitle(String site);

  /// Title of the registration panel.
  ///
  /// In en, this message translates to:
  /// **'Registration'**
  String get registrationTitle;

  /// Says what a character link means.
  ///
  /// In en, this message translates to:
  /// **'Your character pages are unlisted: anybody with the link can open them.'**
  String get unlistedText;

  /// What to do after a reinstall, which makes a new key.
  ///
  /// In en, this message translates to:
  /// **'If you reinstall the app, ask the website admin to move your characters to your new key.'**
  String get lostKeyText;

  /// Label of the website address field.
  ///
  /// In en, this message translates to:
  /// **'Website address'**
  String get websiteAddressLabel;

  /// Label of the button that checks the website.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get checkSiteLabel;

  /// Label of the invite code field.
  ///
  /// In en, this message translates to:
  /// **'Invite code'**
  String get inviteCodeLabel;

  /// Label of the Register button.
  ///
  /// In en, this message translates to:
  /// **'Register'**
  String get registerLabel;

  /// Title of the Upload switch.
  ///
  /// In en, this message translates to:
  /// **'Upload'**
  String get uploadSwitchTitle;

  /// Subtitle of the Upload switch.
  ///
  /// In en, this message translates to:
  /// **'Send your journey to the website after each gather.'**
  String get uploadSwitchSubtitle;

  /// Label of the Upload now button.
  ///
  /// In en, this message translates to:
  /// **'Upload now'**
  String get uploadNowLabel;

  /// Label of the upload button and the progress while an upload runs.
  ///
  /// In en, this message translates to:
  /// **'Uploading…'**
  String get uploadingLabel;

  /// Screen reader label of the upload button while an upload runs.
  ///
  /// In en, this message translates to:
  /// **'Uploading, please wait'**
  String get uploadingSemantics;

  /// Shown when the website stayed busy.
  ///
  /// In en, this message translates to:
  /// **'Upload paused. It continues after the next gather.'**
  String get uploadPausedText;

  /// Label of the button that asks the admin to approve screenshots.
  ///
  /// In en, this message translates to:
  /// **'Request screenshots'**
  String get requestScreenshotsLabel;

  /// Label of the button that copies a character link.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copyLinkLabel;

  /// Screen reader label of the Copy link button.
  ///
  /// In en, this message translates to:
  /// **'Copy link of {name}'**
  String copyLinkSemantics(String name);

  /// Label of the button that removes a character, and title of its dialog.
  ///
  /// In en, this message translates to:
  /// **'Remove from website'**
  String get removeFromWebsiteLabel;

  /// Screen reader label of the Remove from website button.
  ///
  /// In en, this message translates to:
  /// **'Remove {name} from website'**
  String removeFromWebsiteSemantics(String name);

  /// Shown after a link was copied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get linkCopiedText;

  /// Label of the button that confirms a removal.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeLabel;

  /// Result of Check on a website with open registration.
  ///
  /// In en, this message translates to:
  /// **'Found {name}. Anybody can register here.'**
  String siteFoundOpen(String name);

  /// Result of Check on a website that asks for an invite code.
  ///
  /// In en, this message translates to:
  /// **'Found {name}. You need an invite code from the website admin to register.'**
  String siteFoundInvite(String name);

  /// Shown when the website answered, but not as a Memories website.
  ///
  /// In en, this message translates to:
  /// **'This address does not look like a Memories website. Check the address.'**
  String get notAMemoriesSite;

  /// The registration line of the settings.
  ///
  /// In en, this message translates to:
  /// **'Registered on {site}.'**
  String registeredText(String site);

  /// The registration line of the settings.
  ///
  /// In en, this message translates to:
  /// **'Not registered on {site}. Register to upload your journey.'**
  String notRegisteredText(String site);

  /// The fingerprint of the key of the app.
  ///
  /// In en, this message translates to:
  /// **'Your key: {fingerprint}'**
  String fingerprintText(String fingerprint);

  /// Screenshot state: none.
  ///
  /// In en, this message translates to:
  /// **'Screenshots are not uploaded. Ask the website admin to approve them.'**
  String get screenshotsNone;

  /// Screenshot state: pending.
  ///
  /// In en, this message translates to:
  /// **'Waiting for the website admin to approve your screenshots.'**
  String get screenshotsPending;

  /// Screenshot state: approved.
  ///
  /// In en, this message translates to:
  /// **'Your screenshots are uploaded with your journey.'**
  String get screenshotsApproved;

  /// Screenshot state: denied.
  ///
  /// In en, this message translates to:
  /// **'The website admin did not approve screenshots. You can ask again.'**
  String get screenshotsDenied;

  /// Shown on the Website card when the key is not registered.
  ///
  /// In en, this message translates to:
  /// **'You are not registered on {site}. Register below to share your journey.'**
  String cardNotRegistered(String site);

  /// Shown on the Website card when Upload is off.
  ///
  /// In en, this message translates to:
  /// **'Upload is off. Turn on the Upload switch below to send your journey.'**
  String get cardUploadOff;

  /// Text under the progress bar of a running upload.
  ///
  /// In en, this message translates to:
  /// **'Uploading {done} of {total}'**
  String uploadProgress(int done, int total);

  /// Shown before the first upload of this run.
  ///
  /// In en, this message translates to:
  /// **'Nothing uploaded yet.'**
  String get lastUploadNever;

  /// The time of the last upload.
  ///
  /// In en, this message translates to:
  /// **'Last upload {time}'**
  String lastUpload(String time);

  /// Part of the upload summary. Starts with a lower case letter; the app capitalizes the first part.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{uploaded 1 character} other{uploaded {count} characters}}'**
  String syncUploaded(int count);

  /// Part of the upload summary. Starts with a lower case letter.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{sent 1 screenshot} other{sent {count} screenshots}}'**
  String syncShots(int count);

  /// Part of the upload summary when nothing changed. Starts with a lower case letter.
  ///
  /// In en, this message translates to:
  /// **'everything is up to date'**
  String get syncUpToDate;

  /// Part of the upload summary. Starts with a lower case letter.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{skipped 1 removed character (Upload now sends it again)} other{skipped {count} removed characters (Upload now sends them again)}}'**
  String syncRemoved(int count);

  /// Part of the upload summary. Starts with a lower case letter.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 character failed} other{{count} characters failed}}'**
  String syncFailed(int count);

  /// Part of the upload summary. Starts with a lower case letter.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 screenshot failed} other{{count} screenshots failed}}'**
  String syncShotsFailed(int count);

  /// Upload error: the network failed. {host} is a host name.
  ///
  /// In en, this message translates to:
  /// **'Could not reach {host}. Check the internet connection and the website address.'**
  String errNetwork(String host);

  /// Upload error: the answer is not valid.
  ///
  /// In en, this message translates to:
  /// **'The website sent an answer that this program does not understand. Check the website address.'**
  String get errBadResponse;

  /// Upload error: a file to upload is missing.
  ///
  /// In en, this message translates to:
  /// **'A file of your journey is missing or cannot be read, so it was not uploaded. Gather again, then try again.'**
  String get errBadFiles;

  /// Upload error: the index is missing. index.json is a file name.
  ///
  /// In en, this message translates to:
  /// **'Could not read index.json of the latest data. Run the gather first, then try again.'**
  String get errNoIndex;

  /// Upload error: the key file has a problem.
  ///
  /// In en, this message translates to:
  /// **'The key file of the app cannot be read or written. Check its permissions and the free space of its folder.'**
  String get errBadKey;

  /// Upload error: the website address is not valid.
  ///
  /// In en, this message translates to:
  /// **'The website address is not valid. Write it like https://example.com.'**
  String get errBadSite;

  /// Upload error: the state file could not be written.
  ///
  /// In en, this message translates to:
  /// **'The character was removed from the website, but the app could not save that, so the next gather may upload it again. Check that the app folder can be written to.'**
  String get errBadState;

  /// Upload error: an internal failure.
  ///
  /// In en, this message translates to:
  /// **'The upload stopped because of a problem inside the app. Try again after the next gather.'**
  String get errFailed;

  /// Upload error: an unexpected HTTP status.
  ///
  /// In en, this message translates to:
  /// **'The website answered with status {status}. Try again later, and check the website address.'**
  String errHttp(String status);

  /// Upload error: the key is blocked.
  ///
  /// In en, this message translates to:
  /// **'The website admin blocked this app\'s key. Uploads to {site} are off.'**
  String errKeyRevoked(String site);

  /// Upload error: the key is not registered.
  ///
  /// In en, this message translates to:
  /// **'The website does not know the key of this app yet. Register in the settings.'**
  String get errNotRegistered;

  /// Upload error: the character belongs to another key.
  ///
  /// In en, this message translates to:
  /// **'Another player already uploaded {name} on {realm}. Ask the website admin.'**
  String errClaimed(String name, String realm);

  /// Stands for the realm of a character when the app does not know it. Used in 'Another player already uploaded NAME on its realm.'
  ///
  /// In en, this message translates to:
  /// **'its realm'**
  String get realmUnknown;

  /// Upload error: the data is rejected.
  ///
  /// In en, this message translates to:
  /// **'The website did not accept the data. Fix the saved files, then upload again.'**
  String get errInvalid;

  /// Upload error: the invite code is wrong.
  ///
  /// In en, this message translates to:
  /// **'The invite code is not valid. Ask the website admin for a new one.'**
  String get errInviteInvalid;

  /// Upload error: the signature failed.
  ///
  /// In en, this message translates to:
  /// **'The website did not accept the signature of the app. Check that the clock of your computer is right, then try again.'**
  String get errBadSignature;

  /// Upload error: the rate limit.
  ///
  /// In en, this message translates to:
  /// **'Too many requests. Wait a minute, then try again.'**
  String get errRateLimited;

  /// Upload error: the server is busy.
  ///
  /// In en, this message translates to:
  /// **'The website is busy with other uploads. Try again in a few minutes.'**
  String get errBusy;

  /// Upload error: the quota is full.
  ///
  /// In en, this message translates to:
  /// **'The website has no more room for your data. Ask the website admin.'**
  String get errQuota;

  /// Upload error: the data is too large.
  ///
  /// In en, this message translates to:
  /// **'Your data is too large for this website. Ask the website admin to raise the limit.'**
  String get errTooLarge;

  /// Upload error: the website failed.
  ///
  /// In en, this message translates to:
  /// **'The website had a problem. Try again in a few minutes.'**
  String get errInternal;

  /// Upload error: the request is not valid.
  ///
  /// In en, this message translates to:
  /// **'The website could not read the request. Try again, and update the app if it keeps happening.'**
  String get errBadRequest;

  /// Upload error: no such character.
  ///
  /// In en, this message translates to:
  /// **'This website has no such character for this key.'**
  String get errNotFound;

  /// Upload error: screenshots are not approved.
  ///
  /// In en, this message translates to:
  /// **'The website admin has not approved your screenshots yet.'**
  String get errScreenshotsNotApproved;

  /// Upload error: the image type is not supported.
  ///
  /// In en, this message translates to:
  /// **'The website did not accept a screenshot because its image type is not supported.'**
  String get errUnsupportedImage;

  /// Upload error: the screenshot is not used by the journal.
  ///
  /// In en, this message translates to:
  /// **'A screenshot does not belong to any journal line, so the website did not keep it.'**
  String get errNotReferenced;

  /// Upload error: the character id does not match.
  ///
  /// In en, this message translates to:
  /// **'This character name already belongs to another character on the website. Ask the website admin.'**
  String get errGuidMismatch;

  /// Upload error: the upload is not compressed.
  ///
  /// In en, this message translates to:
  /// **'The upload was not compressed as the website needs. Update the app, then try again.'**
  String get errGzipRequired;

  /// An upload error for one character.
  ///
  /// In en, this message translates to:
  /// **'{name}: {text}'**
  String namedError(String name, String text);

  /// A rejected upload. {problems} is the first 3 problems from the website, in English, ending with a full stop.
  ///
  /// In en, this message translates to:
  /// **'The website did not accept the data of {name}: {problems}{more, plural, =0{} =1{ And 1 more problem.} other{ And {more} more problems.}} Fix the saved files, then upload again.'**
  String rejectedText(String name, String problems, int more);

  /// Address check: not valid.
  ///
  /// In en, this message translates to:
  /// **'The website address is not valid. Write it like https://example.com.'**
  String get siteInvalid;

  /// Address check: no scheme or host.
  ///
  /// In en, this message translates to:
  /// **'The website address needs a scheme and a host, like https://example.com.'**
  String get siteNeedsHost;

  /// Address check: another scheme.
  ///
  /// In en, this message translates to:
  /// **'The website address must start with https://.'**
  String get siteNeedsHttps;

  /// Address check: http on a non-local host.
  ///
  /// In en, this message translates to:
  /// **'The website address must start with https://. Plain http:// is only allowed for localhost, 127.0.0.1 and [::1].'**
  String get siteHttpLoopback;

  /// Address check: user name or password.
  ///
  /// In en, this message translates to:
  /// **'The website address may not hold a user name or a password.'**
  String get siteUserInfo;

  /// Address check: query or fragment.
  ///
  /// In en, this message translates to:
  /// **'The website address may not hold a query or a fragment.'**
  String get siteQuery;

  /// Address check: a path.
  ///
  /// In en, this message translates to:
  /// **'The website address may not hold a path. Use the address of the site itself, like https://example.com.'**
  String get sitePath;

  /// The question before a character leaves the website.
  ///
  /// In en, this message translates to:
  /// **'Remove {name} from {site}? The page and its data are deleted.'**
  String removeQuestionText(String name, String site);

  /// Shown after a character was removed from the website.
  ///
  /// In en, this message translates to:
  /// **'{name} was removed from the website. Gathers do not upload it again; Upload now does.'**
  String removedText(String name);

  /// Shown when an action starts while an upload runs.
  ///
  /// In en, this message translates to:
  /// **'The app is busy with the website. Try again when the upload ends.'**
  String get busyText;

  /// Shown when an action failed for an unforeseen reason.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong with the website. Try again in a few minutes.'**
  String get genericFailureText;

  /// Shown when another copy runs but did not answer.
  ///
  /// In en, this message translates to:
  /// **'WoW Journey is already running, but it did not answer. Quit it from its tray icon menu, or end it in the task manager, then start it again.'**
  String get notAnswering;

  /// Label of the button that closes the app.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// Tray menu item.
  ///
  /// In en, this message translates to:
  /// **'Gather now'**
  String get trayGatherNow;

  /// Tray menu item.
  ///
  /// In en, this message translates to:
  /// **'Open window'**
  String get trayOpenWindow;

  /// Tray menu item.
  ///
  /// In en, this message translates to:
  /// **'Open backup folder'**
  String get trayOpenBackupFolder;

  /// Tray menu item.
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get trayQuit;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) => <String>[
    'de',
    'en',
    'es',
    'fr',
    'it',
    'pt',
  ].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'it':
      return AppLocalizationsIt();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
