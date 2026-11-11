// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Italian (`it`).
class AppLocalizationsIt extends AppLocalizations {
  AppLocalizationsIt([String locale = 'it']) : super(locale);

  @override
  String get appTitle => 'WoW Journey';

  @override
  String get loadingSettings => 'Caricamento delle impostazioni';

  @override
  String get tabOverview => 'Panoramica';

  @override
  String get tabWebsite => 'Sito web';

  @override
  String get tabSettings => 'Impostazioni';

  @override
  String get noDataText =>
      'Ancora nessun dato di Memories. Gioca con gli addon Memories attivi, poi esci dal gioco.';

  @override
  String get wowFolderGoneText =>
      'Non troviamo più la tua cartella di WoW. Potrebbe essere stata spostata, oppure la sua unità non è collegata. Scegli di nuovo la cartella.';

  @override
  String get saveHintText =>
      'Il gioco salva il tuo viaggio quando esci o digiti /reload.';

  @override
  String get watchingText => 'Controllo dei cambiamenti';

  @override
  String get issueNoWtf =>
      'Questa cartella non contiene file di gioco di WoW. Scegli la cartella di una versione del gioco, come _retail_.';

  @override
  String get issueDamagedFile =>
      'Non è stato possibile leggere un file salvato, quindi l’abbiamo saltato. Accedi con quel personaggio, esci e riprova.';

  @override
  String get issueAccountSkipped =>
      'Il file Memories di un account manca o è danneggiato, quindi abbiamo saltato i suoi personaggi. Accedi una volta, esci e riprova.';

  @override
  String get issueCharacterFailed =>
      'Non siamo riusciti ad aggiornare i dati di un personaggio e li abbiamo lasciati com’erano. Controlla la sua cartella negli ultimi dati, poi riprova.';

  @override
  String get issueOverlap =>
      'La cartella di backup è dentro i file del gioco. Scegli una cartella di backup fuori dalla cartella di World of Warcraft.';

  @override
  String get issueLockHeld =>
      'Un’altra raccolta è in corso su questa cartella di backup. Attendi che finisca, poi riprova.';

  @override
  String get issueNotWritable =>
      'Non possiamo scrivere nella cartella di backup. Controlla che la sua unità sia collegata e abbia spazio libero, oppure scegli un’altra cartella di backup.';

  @override
  String get issueBadIndex =>
      'Il file index.json degli ultimi dati è danneggiato. Spostalo fuori dalla cartella, poi riprova.';

  @override
  String get issueBadDefault =>
      'Il primo personaggio da mostrare non è nei tuoi dati. Riprova.';

  @override
  String get issueSkippedFile =>
      'Un file salvato non aveva dati di Memories o apparteneva a un altro personaggio, quindi l’abbiamo saltato.';

  @override
  String get issueDuplicateGuid =>
      'Due cartelle contengono lo stesso personaggio. Abbiamo tenuto quella che hai giocato per ultima.';

  @override
  String get issueBackupFailed =>
      'Non siamo riusciti a copiare un file salvato nella cartella di backup. Controlla che la sua unità abbia spazio libero, poi riprova.';

  @override
  String get issueScreenshotFailed =>
      'Non siamo riusciti a copiare uno screenshot. Controlla che l’unità abbia spazio libero, poi riprova.';

  @override
  String get issueIoError =>
      'Non è stato possibile leggere o scrivere un file, quindi la raccolta si è fermata. Controlla che le tue unità siano collegate e abbiano spazio libero, poi riprova.';

  @override
  String get fixChooseWowFolder => 'Scegli cartella';

  @override
  String get fixChooseBackupFolder => 'Scegli cartella di backup';

  @override
  String get fixOpenLatest => 'Apri gli ultimi dati';

  @override
  String get fixTryAgain => 'Riprova';

  @override
  String get statusGathering => 'Raccolta del tuo viaggio…';

  @override
  String get statusFailed =>
      'L’ultima raccolta non è terminata. Vedi il problema qui sotto.';

  @override
  String statusDoneProblems(String when) {
    return 'Raccolto con problemi. Ultima raccolta $when';
  }

  @override
  String statusDone(String when) {
    return 'Aggiornato. Ultima raccolta $when';
  }

  @override
  String statusIdleLast(String when) {
    return 'Ultima raccolta $when';
  }

  @override
  String get statusNever => 'Mai raccolto';

  @override
  String statusSemantics(String status) {
    return 'Stato: $status';
  }

  @override
  String get gathering => 'Raccolta…';

  @override
  String get gatheringSemantics => 'Raccolta in corso, attendi';

  @override
  String get gatheringProgress => 'Raccolta';

  @override
  String get gatherNow => 'Raccogli ora';

  @override
  String get countCharacters => 'Personaggi';

  @override
  String get countJournalLines => 'Righe del diario';

  @override
  String get countScreenshots => 'Screenshot';

  @override
  String countSemantics(String label, int value) {
    return '$label: $value';
  }

  @override
  String get charactersTitle => 'Personaggi';

  @override
  String get noCharacters =>
      'Ancora nessun personaggio. Fai clic su Raccogli ora.';

  @override
  String characterLevel(int level) {
    return 'Livello $level';
  }

  @override
  String get backupFolderTitle => 'Cartella di backup';

  @override
  String get notSet => 'Non impostata';

  @override
  String backupSize(String size) {
    return 'Dimensione: $size';
  }

  @override
  String get openBackupFolder => 'Apri la cartella di backup';

  @override
  String get openLatestData => 'Apri gli ultimi dati';

  @override
  String get openFolderFailed =>
      'Non siamo riusciti ad aprire questa cartella. Se non hai ancora raccolto, fai prima clic su Raccogli ora.';

  @override
  String get viewCharacter => 'Visualizza';

  @override
  String viewCharacterLabel(String name) {
    return 'Visualizza $name';
  }

  @override
  String get viewerStartFailed =>
      'Impossibile avviare il visualizzatore del viaggio.';

  @override
  String get viewerOpenFailed =>
      'Non siamo riusciti ad aprire il browser. Copia il link e aprilo tu stesso.';

  @override
  String get dismiss => 'Chiudi';

  @override
  String get showWebsiteTab => 'Mostra la scheda Sito web';

  @override
  String andMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'e altri $count',
      one: 'e 1 altro',
    );
    return '$_temp0';
  }

  @override
  String sizeBytes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count byte',
      one: '1 byte',
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
  String get classWarrior => 'Guerriero';

  @override
  String get classPaladin => 'Paladino';

  @override
  String get classHunter => 'Cacciatore';

  @override
  String get classRogue => 'Ladro';

  @override
  String get classPriest => 'Sacerdote';

  @override
  String get classDeathKnight => 'Cavaliere della Morte';

  @override
  String get classShaman => 'Sciamano';

  @override
  String get classMage => 'Mago';

  @override
  String get classWarlock => 'Stregone';

  @override
  String get classMonk => 'Monaco';

  @override
  String get classDruid => 'Druido';

  @override
  String get classDemonHunter => 'Cacciatore di Demoni';

  @override
  String get classEvoker => 'Evocatore';

  @override
  String get settingsSaveFailed =>
      'Non siamo riusciti a salvare le tue impostazioni. Controlla che il disco abbia spazio libero, poi cambia di nuovo l’impostazione.';

  @override
  String get settingsDamaged =>
      'Il file delle impostazioni era danneggiato, quindi l’app è partita con le impostazioni predefinite. Controlla le tue cartelle e i tuoi interruttori.';

  @override
  String get wowFolderTitle => 'Cartella di WoW';

  @override
  String get changeWowFolderSemantics => 'Cambia la cartella di WoW';

  @override
  String get changeBackupFolderSemantics => 'Cambia la cartella di backup';

  @override
  String get change => 'Cambia';

  @override
  String get watchTitle => 'Controllo';

  @override
  String get watchSubtitle => 'Raccogli da solo ogni volta che il gioco salva.';

  @override
  String get startAtLoginTitle => 'Avvia all’accesso';

  @override
  String get startAtLoginSubtitle => 'Avvia l’app nascosta quando accedi.';

  @override
  String get languageTitle => 'Lingua';

  @override
  String get languageSystem => 'Sistema';

  @override
  String get versionTitle => 'Versione';

  @override
  String versionText(String version, String core) {
    return 'WoW Journey $version, $core';
  }

  @override
  String get wizardTitle => 'Benvenuto in WoW Journey';

  @override
  String wizardStep(int step, int total) {
    return 'Passo $step di $total';
  }

  @override
  String get back => 'Indietro';

  @override
  String backSemantics(int step) {
    return 'Torna al passo $step';
  }

  @override
  String get next => 'Avanti';

  @override
  String get nextSemantics => 'Passo successivo';

  @override
  String get finish => 'Fine';

  @override
  String get finishSemantics => 'Termina la configurazione';

  @override
  String get wowStepTitle => 'La tua cartella di WoW';

  @override
  String get wowStepIntro =>
      'Leggiamo i file che gli addon Memories salvano in questa cartella. Non li modifichiamo mai.';

  @override
  String get lookingForWow => 'Ricerca di World of Warcraft…';

  @override
  String get noWowFound =>
      'Non siamo riusciti a trovare World of Warcraft. Scegli la cartella di una versione del gioco, come _retail_, dentro la tua cartella di World of Warcraft.';

  @override
  String get chooseFolder => 'Scegli cartella';

  @override
  String get chooseWowSemantics => 'Scegli la cartella di WoW';

  @override
  String get noMemoriesYet => 'Ancora nessun dato di Memories.';

  @override
  String wowFolderSemantics(String path) {
    return 'Cartella di WoW: $path';
  }

  @override
  String get backupStepTitle => 'La tua cartella di backup';

  @override
  String get backupStepIntro =>
      'Qui teniamo una copia dei tuoi file di gioco e dei tuoi screenshot.';

  @override
  String backupFolderSemantics(String path) {
    return 'Cartella di backup: $path';
  }

  @override
  String get backupFolderSemanticsNotSet => 'Cartella di backup: non impostata';

  @override
  String get chooseBackupPrompt => 'Scegli una cartella di backup.';

  @override
  String get switchStepTitle => 'Come funziona l’app';

  @override
  String get switchStepIntro =>
      'Puoi cambiare queste scelte più tardi nelle Impostazioni.';

  @override
  String get useThisFolder => 'Usa questa cartella';

  @override
  String get pickerFailed =>
      'Non siamo riusciti ad aprire il selettore di cartelle. Riprova, oppure riavvia l’app.';

  @override
  String get checkFailed =>
      'Non siamo riusciti a controllare questa cartella. Riprova, oppure scegli un’altra cartella.';

  @override
  String get chooseGameVersion => 'Scegli una versione del gioco';

  @override
  String get backupInsideWow =>
      'Questa cartella è dentro la tua cartella di World of Warcraft, oppure la contiene. Scegli una cartella di backup fuori dalla cartella del gioco.';

  @override
  String get backupInsideWowFirst =>
      'La tua cartella di backup è dentro questa cartella di World of Warcraft, oppure la contiene. Scegli prima un’altra cartella di backup, poi questa cartella di WoW.';

  @override
  String get useBackupTitle => 'Usare questa cartella di backup?';

  @override
  String useBackupBody(String path) {
    return 'Le nuove raccolte vanno in $path. La tua vecchia cartella di backup resta com’è. Non la spostiamo e non la eliminiamo.';
  }

  @override
  String get cancel => 'Annulla';

  @override
  String get flavorReady => 'Questa cartella di WoW è pronta.';

  @override
  String get flavorReadyNoData =>
      'Questa cartella di WoW è pronta, ma non ha ancora dati di Memories. Gioca con gli addon Memories attivi. Il gioco salva i suoi file quando esci o digiti /reload.';

  @override
  String get flavorNoWtf =>
      'Questa cartella non è una cartella di gioco di WoW. Non ha la cartella WTF/Account. Scegli la cartella di una versione del gioco dentro la tua cartella di World of Warcraft, come _retail_.';

  @override
  String flavorInstallFolder(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Questa è la cartella di World of Warcraft. Contiene $count versioni del gioco: $names. Scegline una.',
      one:
          'Questa è la cartella di World of Warcraft. Contiene una versione del gioco: $names. Scegli quella cartella.',
    );
    return '$_temp0';
  }

  @override
  String get flavorNotADirectory =>
      'Questa non è una cartella, oppure non esiste più. Scegli una cartella.';

  @override
  String get flavorNotReadable =>
      'Questa cartella, o una cartella al suo interno, non può essere letta. Controlla che il tuo utente possa aprirla, poi scegli di nuovo.';

  @override
  String get websiteTitle => 'Sito web';

  @override
  String websiteCardTitle(String site) {
    return 'Sito web: $site';
  }

  @override
  String get registrationTitle => 'Registrazione';

  @override
  String get unlistedText =>
      'Le pagine dei tuoi personaggi non sono in elenco: chiunque abbia il link può aprirle.';

  @override
  String get lostKeyText =>
      'Se reinstalli l’app o crei una nuova chiave, copia la tua nuova chiave e chiedi all’amministratore del sito di spostare i tuoi personaggi su di essa.';

  @override
  String get websiteAddressLabel => 'Indirizzo del sito web';

  @override
  String get checkSiteLabel => 'Controlla';

  @override
  String get inviteCodeLabel => 'Codice d’invito';

  @override
  String get registerLabel => 'Registrati';

  @override
  String get uploadSwitchTitle => 'Caricamento';

  @override
  String get uploadSwitchSubtitle =>
      'Invia il tuo viaggio al sito web dopo ogni raccolta.';

  @override
  String get uploadNowLabel => 'Carica ora';

  @override
  String get uploadingLabel => 'Caricamento…';

  @override
  String get uploadingSemantics => 'Caricamento in corso, attendi';

  @override
  String get uploadPausedText =>
      'Caricamento in pausa. Continua dopo la prossima raccolta.';

  @override
  String get requestScreenshotsLabel => 'Richiedi gli screenshot';

  @override
  String get copyLinkLabel => 'Copia il link';

  @override
  String copyLinkSemantics(String name) {
    return 'Copia il link di $name';
  }

  @override
  String get removeFromWebsiteLabel => 'Rimuovi dal sito web';

  @override
  String removeFromWebsiteSemantics(String name) {
    return 'Rimuovi $name dal sito web';
  }

  @override
  String get linkCopiedText => 'Link copiato';

  @override
  String get removeLabel => 'Rimuovi';

  @override
  String siteFoundOpen(String name) {
    return '$name trovato. Qui può registrarsi chiunque.';
  }

  @override
  String siteFoundInvite(String name) {
    return '$name trovato. Per registrarti ti serve un codice d’invito dell’amministratore del sito.';
  }

  @override
  String get notAMemoriesSite =>
      'Questo indirizzo non sembra un sito web Memories. Controlla l’indirizzo.';

  @override
  String registeredText(String site) {
    return 'Registrato su $site.';
  }

  @override
  String notRegisteredText(String site) {
    return 'Non registrato su $site. Registrati per caricare il tuo viaggio.';
  }

  @override
  String fingerprintText(String fingerprint) {
    return 'La tua chiave: $fingerprint';
  }

  @override
  String get copyKeyLabel => 'Copia la tua chiave';

  @override
  String get copyKeySemantics =>
      'Copia la tua chiave per l’amministratore del sito';

  @override
  String get keyCopiedText => 'Chiave copiata';

  @override
  String get newKeyLabel => 'Crea una nuova chiave';

  @override
  String get newKeyTitle => 'Creare una nuova chiave?';

  @override
  String newKeyQuestionText(String site) {
    return 'Fallo solo se il sito web ha bloccato o rifiutato questa chiave. L’app crea una nuova chiave e tiene una copia di quella vecchia. I tuoi personaggi su $site restano legati alla vecchia chiave. L’amministratore del sito può spostarli sulla nuova chiave. Poi registrati di nuovo. Il sito web può chiedere un nuovo codice d’invito. L’app carica di nuovo i tuoi personaggi selezionati. Il caricamento resta disattivato finché non lo attivi.';
  }

  @override
  String get newKeyDoneText =>
      'Nuova chiave creata. Registrati di nuovo per caricare.';

  @override
  String get errKeyNotReplaced =>
      'L’app non è riuscita a creare una nuova chiave, quindi tiene quella vecchia. Controlla che la sua cartella sia scrivibile e abbia spazio libero, poi riprova.';

  @override
  String get screenshotsNone =>
      'Gli screenshot non vengono caricati. Chiedi all’amministratore del sito di approvarli.';

  @override
  String get screenshotsPending =>
      'In attesa che l’amministratore del sito approvi i tuoi screenshot.';

  @override
  String get screenshotsApproved =>
      'I tuoi screenshot vengono caricati con il tuo viaggio.';

  @override
  String get screenshotsDenied =>
      'L’amministratore del sito non ha approvato gli screenshot. Puoi chiedere di nuovo.';

  @override
  String cardNotRegistered(String site) {
    return 'Non sei registrato su $site. Registrati qui sotto per condividere il tuo viaggio.';
  }

  @override
  String get cardUploadOff =>
      'Il caricamento è disattivato. Attiva l’interruttore Caricamento qui sotto per inviare il tuo viaggio.';

  @override
  String get selectionTitle => 'Personaggi da caricare';

  @override
  String get selectionHint => 'Scegli i personaggi da caricare.';

  @override
  String get selectionNote =>
      'I nuovi personaggi non vengono caricati finché non li selezioni. Deselezionare un personaggio ferma solo i caricamenti successivi; non viene rimosso nulla dal sito web.';

  @override
  String get selectAllLabel => 'Seleziona tutto';

  @override
  String get selectNoneLabel => 'Deseleziona tutto';

  @override
  String uploadProgress(int done, int total) {
    return 'Caricamento $done di $total';
  }

  @override
  String get lastUploadNever => 'Ancora nulla di caricato.';

  @override
  String lastUpload(String time) {
    return 'Ultimo caricamento $time';
  }

  @override
  String syncUploaded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count personaggi caricati',
      one: '1 personaggio caricato',
    );
    return '$_temp0';
  }

  @override
  String syncShots(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count screenshot inviati',
      one: '1 screenshot inviato',
    );
    return '$_temp0';
  }

  @override
  String get syncUpToDate => 'tutto è aggiornato';

  @override
  String syncFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count personaggi non riusciti',
      one: '1 personaggio non riuscito',
    );
    return '$_temp0';
  }

  @override
  String syncShotsFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count screenshot non riusciti',
      one: '1 screenshot non riuscito',
    );
    return '$_temp0';
  }

  @override
  String errNetwork(String host) {
    return 'Impossibile raggiungere $host. Controlla la connessione a internet e l’indirizzo del sito web.';
  }

  @override
  String get errBadResponse =>
      'Il sito web ha inviato una risposta che questo programma non capisce. Controlla l’indirizzo del sito web.';

  @override
  String get errBadFiles =>
      'Un file del tuo viaggio manca o non può essere letto, quindi non è stato caricato. Raccogli di nuovo, poi riprova.';

  @override
  String get errNoIndex =>
      'Impossibile leggere index.json degli ultimi dati. Esegui prima la raccolta, poi riprova.';

  @override
  String get errBadKey =>
      'Il file della chiave dell’app non può essere letto o scritto. Controlla i suoi permessi e lo spazio libero della sua cartella.';

  @override
  String get errBadSite =>
      'L’indirizzo del sito web non è valido. Scrivilo così: https://example.com.';

  @override
  String get errBadState =>
      'L’app non ha potuto salvare la tua scelta dei personaggi da caricare. Controlla che si possa scrivere nella cartella dell’app, poi riprova.';

  @override
  String get errFailed =>
      'Il caricamento si è fermato per un problema dentro l’app. Riprova dopo la prossima raccolta.';

  @override
  String errHttp(String status) {
    return 'Il sito web ha risposto con lo stato $status. Riprova più tardi e controlla l’indirizzo del sito web.';
  }

  @override
  String errKeyRevoked(String site) {
    return 'L’amministratore del sito web ha bloccato la chiave di questa app. I caricamenti verso $site sono disattivati.';
  }

  @override
  String get errNotRegistered =>
      'Il sito web non conosce ancora la chiave di questa app. Registrati nella scheda Sito web.';

  @override
  String errClaimed(String name, String realm) {
    return 'Un altro giocatore ha già caricato $name su $realm. Chiedi all’amministratore del sito web.';
  }

  @override
  String get realmUnknown => 'il suo reame';

  @override
  String get errInvalid =>
      'Il sito web non ha accettato i dati. Correggi i file salvati, poi carica di nuovo.';

  @override
  String get errInviteInvalid =>
      'Il codice d’invito non è valido. Chiedine uno nuovo all’amministratore del sito web.';

  @override
  String get errBadSignature =>
      'Il sito web non ha accettato la firma dell’app. Controlla che l’orologio del tuo computer sia corretto, poi riprova.';

  @override
  String get errRateLimited =>
      'Troppe richieste. Attendi un minuto, poi riprova.';

  @override
  String get errBusy =>
      'Il sito web è occupato con altri caricamenti. Riprova tra qualche minuto.';

  @override
  String get errQuota =>
      'Il sito web non ha più spazio per i tuoi dati. Chiedi all’amministratore del sito web.';

  @override
  String get errTooLarge =>
      'I tuoi dati sono troppo grandi per questo sito web. Chiedi all’amministratore del sito web di alzare il limite.';

  @override
  String get errInternal =>
      'Il sito web ha avuto un problema. Riprova tra qualche minuto.';

  @override
  String get errBadRequest =>
      'Il sito web non ha potuto leggere la richiesta. Riprova e aggiorna l’app se continua a succedere.';

  @override
  String get errNotFound =>
      'Questo sito web non ha un personaggio così per questa chiave.';

  @override
  String get errScreenshotsNotApproved =>
      'L’amministratore del sito web non ha ancora approvato i tuoi screenshot.';

  @override
  String get errUnsupportedImage =>
      'Il sito web non ha accettato uno screenshot perché il suo tipo di immagine non è supportato.';

  @override
  String get errNotReferenced =>
      'Uno screenshot non appartiene a nessuna riga del diario, quindi il sito web non l’ha conservato.';

  @override
  String get errGuidMismatch =>
      'Questo nome di personaggio appartiene già a un altro personaggio sul sito web. Chiedi all’amministratore del sito web.';

  @override
  String get errGzipRequired =>
      'Il caricamento non era compresso come richiede il sito web. Aggiorna l’app, poi riprova.';

  @override
  String namedError(String name, String text) {
    return '$name: $text';
  }

  @override
  String rejectedText(String name, String problems, int more) {
    String _temp0 = intl.Intl.pluralLogic(
      more,
      locale: localeName,
      other: ' E altri $more problemi.',
      one: ' E 1 altro problema.',
      zero: '',
    );
    return 'Il sito web non ha accettato i dati di $name: $problems$_temp0 Correggi i file salvati, poi carica di nuovo.';
  }

  @override
  String get siteInvalid =>
      'L’indirizzo del sito web non è valido. Scrivilo così: https://example.com.';

  @override
  String get siteNeedsHost =>
      'L’indirizzo del sito web ha bisogno di uno schema e di un host, come https://example.com.';

  @override
  String get siteNeedsHttps =>
      'L’indirizzo del sito web deve iniziare con https://.';

  @override
  String get siteHttpLoopback =>
      'L’indirizzo del sito web deve iniziare con https://. Il semplice http:// è consentito solo per localhost, 127.0.0.1 e [::1].';

  @override
  String get siteUserInfo =>
      'L’indirizzo del sito web non può contenere un nome utente o una password.';

  @override
  String get siteQuery =>
      'L’indirizzo del sito web non può contenere una query o un frammento.';

  @override
  String get sitePath =>
      'L’indirizzo del sito web non può contenere un percorso. Usa l’indirizzo del sito stesso, come https://example.com.';

  @override
  String removeQuestionText(String name, String site) {
    return 'Rimuovere $name da $site? La pagina e i suoi dati vengono eliminati.';
  }

  @override
  String removedText(String name) {
    return '$name è stato rimosso dal sito web e deselezionato. Selezionalo di nuovo per caricarlo.';
  }

  @override
  String get busyText =>
      'L’app è occupata con il sito web. Riprova quando il caricamento finisce.';

  @override
  String get genericFailureText =>
      'Qualcosa è andato storto con il sito web. Riprova tra qualche minuto.';

  @override
  String get notAnswering =>
      'WoW Journey è già in esecuzione, ma non ha risposto. Usa Esci nel menu della sua icona nella barra di sistema, oppure terminalo nel gestore attività, poi avvialo di nuovo.';

  @override
  String get close => 'Chiudi';

  @override
  String get trayGatherNow => 'Raccogli ora';

  @override
  String get trayViewJourney => 'Visualizza il viaggio';

  @override
  String get trayOpenWindow => 'Apri la finestra';

  @override
  String get trayOpenBackupFolder => 'Apri la cartella di backup';

  @override
  String get trayQuit => 'Esci';
}
