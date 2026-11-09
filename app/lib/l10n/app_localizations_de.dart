// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'WoW Journey';

  @override
  String get loadingSettings => 'Einstellungen werden geladen';

  @override
  String get tabOverview => 'Übersicht';

  @override
  String get tabWebsite => 'Webseite';

  @override
  String get tabSettings => 'Einstellungen';

  @override
  String get noDataText =>
      'Noch keine Memories-Daten. Spiele mit den Memories-Addons und melde dich dann ab.';

  @override
  String get wowFolderGoneText =>
      'Wir finden deinen WoW-Ordner nicht mehr. Er wurde vielleicht verschoben, oder sein Laufwerk ist nicht verbunden. Wähle den Ordner erneut.';

  @override
  String get saveHintText =>
      'Das Spiel speichert deine Reise, wenn du dich abmeldest oder /reload eingibst.';

  @override
  String get watchingText => 'Änderungen werden überwacht';

  @override
  String get issueNoWtf =>
      'In diesem Ordner liegen keine WoW-Spieldateien. Wähle den Ordner einer Spielversion, zum Beispiel _retail_.';

  @override
  String get issueDamagedFile =>
      'Eine gespeicherte Datei konnte nicht gelesen werden, daher haben wir sie übersprungen. Melde dich mit diesem Charakter an, melde dich ab und versuche es dann erneut.';

  @override
  String get issueAccountSkipped =>
      'Die Memories-Datei eines Accounts fehlt oder ist beschädigt, daher haben wir seine Charaktere übersprungen. Melde dich einmal an, melde dich ab und versuche es dann erneut.';

  @override
  String get issueCharacterFailed =>
      'Wir konnten die Daten eines Charakters nicht aktualisieren und haben sie unverändert gelassen. Prüfe seinen Ordner in den neuesten Daten und versuche es dann erneut.';

  @override
  String get issueOverlap =>
      'Der Sicherungsordner liegt in den Spieldateien. Wähle einen Sicherungsordner außerhalb des World-of-Warcraft-Ordners.';

  @override
  String get issueLockHeld =>
      'In diesem Sicherungsordner läuft bereits eine andere Sammlung. Warte, bis sie endet, und versuche es dann erneut.';

  @override
  String get issueNotWritable =>
      'Wir können nicht in den Sicherungsordner schreiben. Prüfe, ob sein Laufwerk verbunden ist und freien Platz hat, oder wähle einen anderen Sicherungsordner.';

  @override
  String get issueBadIndex =>
      'Die Datei index.json in den neuesten Daten ist beschädigt. Verschiebe sie aus dem Ordner und versuche es dann erneut.';

  @override
  String get issueBadDefault =>
      'Der erste anzuzeigende Charakter ist nicht in deinen Daten. Versuche es erneut.';

  @override
  String get issueSkippedFile =>
      'Eine gespeicherte Datei enthielt keine Memories-Daten oder gehörte zu einem anderen Charakter, daher haben wir sie übersprungen.';

  @override
  String get issueDuplicateGuid =>
      'Zwei Ordner enthalten denselben Charakter. Wir haben den zuletzt gespielten behalten.';

  @override
  String get issueBackupFailed =>
      'Wir konnten eine gespeicherte Datei nicht in den Sicherungsordner kopieren. Prüfe, ob sein Laufwerk freien Platz hat, und versuche es dann erneut.';

  @override
  String get issueScreenshotFailed =>
      'Wir konnten einen Screenshot nicht kopieren. Prüfe, ob das Laufwerk freien Platz hat, und versuche es dann erneut.';

  @override
  String get issueIoError =>
      'Eine Datei konnte nicht gelesen oder geschrieben werden, daher wurde die Sammlung gestoppt. Prüfe, ob deine Laufwerke verbunden sind und freien Platz haben, und versuche es dann erneut.';

  @override
  String get fixChooseWowFolder => 'Ordner wählen';

  @override
  String get fixChooseBackupFolder => 'Sicherungsordner wählen';

  @override
  String get fixOpenLatest => 'Neueste Daten öffnen';

  @override
  String get fixTryAgain => 'Erneut versuchen';

  @override
  String get statusGathering => 'Deine Reise wird gesammelt…';

  @override
  String get statusFailed =>
      'Die letzte Sammlung wurde nicht beendet. Siehe das Problem unten.';

  @override
  String statusDoneProblems(String when) {
    return 'Mit Problemen gesammelt. Zuletzt gesammelt $when';
  }

  @override
  String statusDone(String when) {
    return 'Auf dem neuesten Stand. Zuletzt gesammelt $when';
  }

  @override
  String statusIdleLast(String when) {
    return 'Zuletzt gesammelt $when';
  }

  @override
  String get statusNever => 'Noch nie gesammelt';

  @override
  String statusSemantics(String status) {
    return 'Status: $status';
  }

  @override
  String get gathering => 'Sammeln…';

  @override
  String get gatheringSemantics => 'Es wird gesammelt, bitte warten';

  @override
  String get gatheringProgress => 'Sammeln';

  @override
  String get gatherNow => 'Jetzt sammeln';

  @override
  String get countCharacters => 'Charaktere';

  @override
  String get countJournalLines => 'Journalzeilen';

  @override
  String get countScreenshots => 'Screenshots';

  @override
  String countSemantics(String label, int value) {
    return '$label: $value';
  }

  @override
  String get charactersTitle => 'Charaktere';

  @override
  String get noCharacters => 'Noch keine Charaktere. Klicke auf Jetzt sammeln.';

  @override
  String characterLevel(int level) {
    return 'Stufe $level';
  }

  @override
  String get backupFolderTitle => 'Sicherungsordner';

  @override
  String get notSet => 'Nicht festgelegt';

  @override
  String backupSize(String size) {
    return 'Größe: $size';
  }

  @override
  String get openBackupFolder => 'Sicherungsordner öffnen';

  @override
  String get openLatestData => 'Neueste Daten öffnen';

  @override
  String get openFolderFailed =>
      'Wir konnten diesen Ordner nicht öffnen. Wenn du noch nicht gesammelt hast, klicke zuerst auf Jetzt sammeln.';

  @override
  String get dismiss => 'Schließen';

  @override
  String get showWebsiteTab => 'Reiter Webseite anzeigen';

  @override
  String andMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'und $count weitere',
      one: 'und 1 weiterer',
    );
    return '$_temp0';
  }

  @override
  String sizeBytes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Bytes',
      one: '1 Byte',
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
  String get classWarrior => 'Krieger';

  @override
  String get classPaladin => 'Paladin';

  @override
  String get classHunter => 'Jäger';

  @override
  String get classRogue => 'Schurke';

  @override
  String get classPriest => 'Priester';

  @override
  String get classDeathKnight => 'Todesritter';

  @override
  String get classShaman => 'Schamane';

  @override
  String get classMage => 'Magier';

  @override
  String get classWarlock => 'Hexenmeister';

  @override
  String get classMonk => 'Mönch';

  @override
  String get classDruid => 'Druide';

  @override
  String get classDemonHunter => 'Dämonenjäger';

  @override
  String get classEvoker => 'Rufer';

  @override
  String get settingsSaveFailed =>
      'Wir konnten deine Einstellungen nicht speichern. Prüfe, ob deine Festplatte freien Platz hat, und ändere die Einstellung dann erneut.';

  @override
  String get settingsDamaged =>
      'Deine Einstellungsdatei war beschädigt, daher startete die App mit den Standardeinstellungen. Prüfe deine Ordner und Schalter.';

  @override
  String get wowFolderTitle => 'WoW-Ordner';

  @override
  String get changeWowFolderSemantics => 'WoW-Ordner ändern';

  @override
  String get changeBackupFolderSemantics => 'Sicherungsordner ändern';

  @override
  String get change => 'Ändern';

  @override
  String get watchTitle => 'Überwachen';

  @override
  String get watchSubtitle =>
      'Automatisch sammeln, sobald das Spiel speichert.';

  @override
  String get startAtLoginTitle => 'Beim Anmelden starten';

  @override
  String get startAtLoginSubtitle =>
      'Die App versteckt starten, wenn du dich anmeldest.';

  @override
  String get languageTitle => 'Sprache';

  @override
  String get languageSystem => 'System';

  @override
  String get versionTitle => 'Version';

  @override
  String versionText(String version, String core) {
    return 'WoW Journey $version, $core';
  }

  @override
  String get wizardTitle => 'Willkommen bei WoW Journey';

  @override
  String wizardStep(int step, int total) {
    return 'Schritt $step von $total';
  }

  @override
  String get back => 'Zurück';

  @override
  String backSemantics(int step) {
    return 'Zurück zu Schritt $step';
  }

  @override
  String get next => 'Weiter';

  @override
  String get nextSemantics => 'Nächster Schritt';

  @override
  String get finish => 'Fertig';

  @override
  String get finishSemantics => 'Einrichtung abschließen';

  @override
  String get wowStepTitle => 'Dein WoW-Ordner';

  @override
  String get wowStepIntro =>
      'Wir lesen die Dateien, die die Memories-Addons in diesem Ordner speichern. Wir ändern sie nie.';

  @override
  String get lookingForWow => 'World of Warcraft wird gesucht…';

  @override
  String get noWowFound =>
      'Wir konnten World of Warcraft nicht finden. Wähle in deinem World-of-Warcraft-Ordner den Ordner einer Spielversion, zum Beispiel _retail_.';

  @override
  String get chooseFolder => 'Ordner wählen';

  @override
  String get chooseWowSemantics => 'WoW-Ordner wählen';

  @override
  String get noMemoriesYet => 'Noch keine Memories-Daten.';

  @override
  String wowFolderSemantics(String path) {
    return 'WoW-Ordner: $path';
  }

  @override
  String get backupStepTitle => 'Dein Sicherungsordner';

  @override
  String get backupStepIntro =>
      'Hier bewahren wir eine Kopie deiner Spieldateien und deiner Screenshots auf.';

  @override
  String backupFolderSemantics(String path) {
    return 'Sicherungsordner: $path';
  }

  @override
  String get backupFolderSemanticsNotSet =>
      'Sicherungsordner: nicht festgelegt';

  @override
  String get chooseBackupPrompt => 'Wähle einen Sicherungsordner.';

  @override
  String get switchStepTitle => 'So läuft die App';

  @override
  String get switchStepIntro =>
      'Du kannst das später in den Einstellungen ändern.';

  @override
  String get useThisFolder => 'Diesen Ordner verwenden';

  @override
  String get pickerFailed =>
      'Wir konnten die Ordnerauswahl nicht öffnen. Versuche es erneut oder starte die App neu.';

  @override
  String get checkFailed =>
      'Wir konnten diesen Ordner nicht prüfen. Versuche es erneut oder wähle einen anderen Ordner.';

  @override
  String get chooseGameVersion => 'Spielversion wählen';

  @override
  String get backupInsideWow =>
      'Dieser Ordner liegt in deinem World-of-Warcraft-Ordner oder enthält ihn. Wähle einen Sicherungsordner außerhalb des Spielordners.';

  @override
  String get backupInsideWowFirst =>
      'Dein Sicherungsordner liegt in diesem World-of-Warcraft-Ordner oder enthält ihn. Wähle zuerst einen anderen Sicherungsordner und dann diesen WoW-Ordner.';

  @override
  String get useBackupTitle => 'Diesen Sicherungsordner verwenden?';

  @override
  String useBackupBody(String path) {
    return 'Neue Sammlungen gehen nach $path. Dein alter Sicherungsordner bleibt unverändert. Wir verschieben oder löschen ihn nicht.';
  }

  @override
  String get cancel => 'Abbrechen';

  @override
  String get flavorReady => 'Dieser WoW-Ordner ist bereit.';

  @override
  String get flavorReadyNoData =>
      'Dieser WoW-Ordner ist bereit, hat aber noch keine Memories-Daten. Spiele mit den Memories-Addons. Das Spiel speichert seine Dateien, wenn du dich abmeldest oder /reload eingibst.';

  @override
  String get flavorNoWtf =>
      'Dieser Ordner ist kein WoW-Spielordner. Er hat keinen Ordner WTF/Account. Wähle in deinem World-of-Warcraft-Ordner den Ordner einer Spielversion, zum Beispiel _retail_.';

  @override
  String flavorInstallFolder(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Das ist der World-of-Warcraft-Ordner. Er enthält $count Spielversionen: $names. Wähle einen davon.',
      one:
          'Das ist der World-of-Warcraft-Ordner. Er enthält eine Spielversion: $names. Wähle diesen Ordner.',
    );
    return '$_temp0';
  }

  @override
  String get flavorNotADirectory =>
      'Das ist kein Ordner, oder er existiert nicht mehr. Wähle einen Ordner.';

  @override
  String get flavorNotReadable =>
      'Dieser Ordner oder ein Ordner darin kann nicht gelesen werden. Prüfe, ob dein Benutzer ihn öffnen darf, und wähle ihn dann erneut.';

  @override
  String get websiteTitle => 'Webseite';

  @override
  String websiteCardTitle(String site) {
    return 'Webseite: $site';
  }

  @override
  String get registrationTitle => 'Registrierung';

  @override
  String get unlistedText =>
      'Deine Charakterseiten sind nicht gelistet: Jeder mit dem Link kann sie öffnen.';

  @override
  String get lostKeyText =>
      'Wenn du die App neu installierst, bitte den Admin der Webseite, deine Charaktere auf deinen neuen Schlüssel zu übertragen.';

  @override
  String get websiteAddressLabel => 'Webseiten-Adresse';

  @override
  String get checkSiteLabel => 'Prüfen';

  @override
  String get inviteCodeLabel => 'Einladungscode';

  @override
  String get registerLabel => 'Registrieren';

  @override
  String get uploadSwitchTitle => 'Hochladen';

  @override
  String get uploadSwitchSubtitle =>
      'Deine Reise nach jeder Sammlung an die Webseite senden.';

  @override
  String get uploadNowLabel => 'Jetzt hochladen';

  @override
  String get uploadingLabel => 'Hochladen…';

  @override
  String get uploadingSemantics => 'Es wird hochgeladen, bitte warten';

  @override
  String get uploadPausedText =>
      'Hochladen pausiert. Es geht nach der nächsten Sammlung weiter.';

  @override
  String get requestScreenshotsLabel => 'Screenshots anfragen';

  @override
  String get copyLinkLabel => 'Link kopieren';

  @override
  String copyLinkSemantics(String name) {
    return 'Link von $name kopieren';
  }

  @override
  String get removeFromWebsiteLabel => 'Von der Webseite entfernen';

  @override
  String removeFromWebsiteSemantics(String name) {
    return '$name von der Webseite entfernen';
  }

  @override
  String get linkCopiedText => 'Link kopiert';

  @override
  String get removeLabel => 'Entfernen';

  @override
  String siteFoundOpen(String name) {
    return '$name gefunden. Hier kann sich jeder registrieren.';
  }

  @override
  String siteFoundInvite(String name) {
    return '$name gefunden. Zum Registrieren brauchst du einen Einladungscode vom Admin der Webseite.';
  }

  @override
  String get notAMemoriesSite =>
      'Diese Adresse sieht nicht nach einer Memories-Webseite aus. Prüfe die Adresse.';

  @override
  String registeredText(String site) {
    return 'Auf $site registriert.';
  }

  @override
  String notRegisteredText(String site) {
    return 'Nicht auf $site registriert. Registriere dich, um deine Reise hochzuladen.';
  }

  @override
  String fingerprintText(String fingerprint) {
    return 'Dein Schlüssel: $fingerprint';
  }

  @override
  String get screenshotsNone =>
      'Screenshots werden nicht hochgeladen. Bitte den Admin der Webseite, sie zu genehmigen.';

  @override
  String get screenshotsPending =>
      'Warten darauf, dass der Admin der Webseite deine Screenshots genehmigt.';

  @override
  String get screenshotsApproved =>
      'Deine Screenshots werden mit deiner Reise hochgeladen.';

  @override
  String get screenshotsDenied =>
      'Der Admin der Webseite hat Screenshots nicht genehmigt. Du kannst erneut anfragen.';

  @override
  String cardNotRegistered(String site) {
    return 'Du bist nicht auf $site registriert. Registriere dich unten, um deine Reise zu teilen.';
  }

  @override
  String get cardUploadOff =>
      'Hochladen ist aus. Schalte unten den Schalter Hochladen ein, um deine Reise zu senden.';

  @override
  String uploadProgress(int done, int total) {
    return 'Hochladen $done von $total';
  }

  @override
  String get lastUploadNever => 'Noch nichts hochgeladen.';

  @override
  String lastUpload(String time) {
    return 'Letzter Upload $time';
  }

  @override
  String syncUploaded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Charaktere hochgeladen',
      one: '1 Charakter hochgeladen',
    );
    return '$_temp0';
  }

  @override
  String syncShots(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Screenshots gesendet',
      one: '1 Screenshot gesendet',
    );
    return '$_temp0';
  }

  @override
  String get syncUpToDate => 'alles ist aktuell';

  @override
  String syncRemoved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count entfernte Charaktere übersprungen (Jetzt hochladen sendet sie erneut)',
      one: '1 entfernten Charakter übersprungen (Jetzt hochladen sendet ihn erneut)',
    );
    return '$_temp0';
  }

  @override
  String syncFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Charaktere fehlgeschlagen',
      one: '1 Charakter fehlgeschlagen',
    );
    return '$_temp0';
  }

  @override
  String syncShotsFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Screenshots fehlgeschlagen',
      one: '1 Screenshot fehlgeschlagen',
    );
    return '$_temp0';
  }

  @override
  String errNetwork(String host) {
    return '$host ist nicht erreichbar. Prüfe die Internetverbindung und die Adresse der Webseite.';
  }

  @override
  String get errBadResponse =>
      'Die Webseite hat eine Antwort gesendet, die dieses Programm nicht versteht. Prüfe die Adresse der Webseite.';

  @override
  String get errBadFiles =>
      'Eine Datei deiner Reise fehlt oder kann nicht gelesen werden, daher wurde sie nicht hochgeladen. Sammle erneut und versuche es dann erneut.';

  @override
  String get errNoIndex =>
      'index.json der neuesten Daten konnte nicht gelesen werden. Führe zuerst die Sammlung aus und versuche es dann erneut.';

  @override
  String get errBadKey =>
      'Die Schlüsseldatei der App kann nicht gelesen oder geschrieben werden. Prüfe ihre Berechtigungen und den freien Platz ihres Ordners.';

  @override
  String get errBadSite =>
      'Die Adresse der Webseite ist ungültig. Schreibe sie so: https://example.com.';

  @override
  String get errBadState =>
      'Der Charakter wurde von der Webseite entfernt, aber die App konnte das nicht speichern, daher wird er bei der nächsten Sammlung eventuell erneut hochgeladen. Prüfe, ob in den App-Ordner geschrieben werden kann.';

  @override
  String get errFailed =>
      'Das Hochladen wurde wegen eines Problems in der App gestoppt. Versuche es nach der nächsten Sammlung erneut.';

  @override
  String errHttp(String status) {
    return 'Die Webseite antwortete mit Status $status. Versuche es später erneut und prüfe die Adresse der Webseite.';
  }

  @override
  String errKeyRevoked(String site) {
    return 'Der Admin der Webseite hat den Schlüssel dieser App gesperrt. Das Hochladen zu $site ist aus.';
  }

  @override
  String get errNotRegistered =>
      'Die Webseite kennt den Schlüssel dieser App noch nicht. Registriere dich im Reiter Webseite.';

  @override
  String errClaimed(String name, String realm) {
    return 'Ein anderer Spieler hat $name auf $realm bereits hochgeladen. Frage den Admin der Webseite.';
  }

  @override
  String get realmUnknown => 'seinem Realm';

  @override
  String get errInvalid =>
      'Die Webseite hat die Daten nicht akzeptiert. Behebe die gespeicherten Dateien und lade dann erneut hoch.';

  @override
  String get errInviteInvalid =>
      'Der Einladungscode ist ungültig. Bitte den Admin der Webseite um einen neuen.';

  @override
  String get errBadSignature =>
      'Die Webseite hat die Signatur der App nicht akzeptiert. Prüfe, ob die Uhr deines Computers richtig geht, und versuche es dann erneut.';

  @override
  String get errRateLimited =>
      'Zu viele Anfragen. Warte eine Minute und versuche es dann erneut.';

  @override
  String get errBusy =>
      'Die Webseite ist mit anderen Uploads beschäftigt. Versuche es in ein paar Minuten erneut.';

  @override
  String get errQuota =>
      'Die Webseite hat keinen Platz mehr für deine Daten. Frage den Admin der Webseite.';

  @override
  String get errTooLarge =>
      'Deine Daten sind für diese Webseite zu groß. Bitte den Admin der Webseite, das Limit zu erhöhen.';

  @override
  String get errInternal =>
      'Die Webseite hatte ein Problem. Versuche es in ein paar Minuten erneut.';

  @override
  String get errBadRequest =>
      'Die Webseite konnte die Anfrage nicht lesen. Versuche es erneut und aktualisiere die App, wenn es weiter passiert.';

  @override
  String get errNotFound =>
      'Diese Webseite hat keinen solchen Charakter für diesen Schlüssel.';

  @override
  String get errScreenshotsNotApproved =>
      'Der Admin der Webseite hat deine Screenshots noch nicht genehmigt.';

  @override
  String get errUnsupportedImage =>
      'Die Webseite hat einen Screenshot nicht akzeptiert, weil sein Bildtyp nicht unterstützt wird.';

  @override
  String get errNotReferenced =>
      'Ein Screenshot gehört zu keiner Journalzeile, daher hat die Webseite ihn nicht behalten.';

  @override
  String get errGuidMismatch =>
      'Dieser Charaktername gehört auf der Webseite bereits zu einem anderen Charakter. Frage den Admin der Webseite.';

  @override
  String get errGzipRequired =>
      'Der Upload war nicht so komprimiert, wie die Webseite es braucht. Aktualisiere die App und versuche es dann erneut.';

  @override
  String namedError(String name, String text) {
    return '$name: $text';
  }

  @override
  String rejectedText(String name, String problems, int more) {
    String _temp0 = intl.Intl.pluralLogic(
      more,
      locale: localeName,
      other: ' Und $more weitere Probleme.',
      one: ' Und 1 weiteres Problem.',
      zero: '',
    );
    return 'Die Webseite hat die Daten von $name nicht akzeptiert: $problems$_temp0 Behebe die gespeicherten Dateien und lade dann erneut hoch.';
  }

  @override
  String get siteInvalid =>
      'Die Adresse der Webseite ist ungültig. Schreibe sie so: https://example.com.';

  @override
  String get siteNeedsHost =>
      'Die Adresse der Webseite braucht ein Schema und einen Host, wie https://example.com.';

  @override
  String get siteNeedsHttps =>
      'Die Adresse der Webseite muss mit https:// beginnen.';

  @override
  String get siteHttpLoopback =>
      'Die Adresse der Webseite muss mit https:// beginnen. Einfaches http:// ist nur für localhost, 127.0.0.1 und [::1] erlaubt.';

  @override
  String get siteUserInfo =>
      'Die Adresse der Webseite darf keinen Benutzernamen und kein Passwort enthalten.';

  @override
  String get siteQuery =>
      'Die Adresse der Webseite darf keine Abfrage und kein Fragment enthalten.';

  @override
  String get sitePath =>
      'Die Adresse der Webseite darf keinen Pfad enthalten. Verwende die Adresse der Seite selbst, wie https://example.com.';

  @override
  String removeQuestionText(String name, String site) {
    return '$name von $site entfernen? Die Seite und ihre Daten werden gelöscht.';
  }

  @override
  String removedText(String name) {
    return '$name wurde von der Webseite entfernt. Sammlungen laden ihn nicht erneut hoch; Jetzt hochladen tut es.';
  }

  @override
  String get busyText =>
      'Die App ist mit der Webseite beschäftigt. Versuche es erneut, wenn der Upload endet.';

  @override
  String get genericFailureText =>
      'Mit der Webseite ist etwas schiefgelaufen. Versuche es in ein paar Minuten erneut.';

  @override
  String get notAnswering =>
      'WoW Journey läuft bereits, hat aber nicht geantwortet. Beende es über das Menü seines Tray-Symbols oder im Task-Manager und starte es dann erneut.';

  @override
  String get close => 'Schließen';

  @override
  String get trayGatherNow => 'Jetzt sammeln';

  @override
  String get trayOpenWindow => 'Fenster öffnen';

  @override
  String get trayOpenBackupFolder => 'Sicherungsordner öffnen';

  @override
  String get trayQuit => 'Beenden';
}
