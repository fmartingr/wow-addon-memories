// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'WoW Journey';

  @override
  String get loadingSettings => 'Chargement de vos réglages';

  @override
  String get tabOverview => 'Aperçu';

  @override
  String get tabWebsite => 'Site web';

  @override
  String get tabSettings => 'Réglages';

  @override
  String get noDataText =>
      'Aucune donnée Memories pour l’instant. Jouez avec les addons Memories activés, puis déconnectez-vous.';

  @override
  String get wowFolderGoneText =>
      'Nous ne trouvons plus votre dossier WoW. Il a peut-être été déplacé, ou son disque n’est pas connecté. Choisissez à nouveau le dossier.';

  @override
  String get saveHintText =>
      'Le jeu enregistre votre parcours quand vous vous déconnectez ou tapez /reload.';

  @override
  String get watchingText => 'Surveillance des changements';

  @override
  String get issueNoWtf =>
      'Ce dossier ne contient pas de fichiers de jeu WoW. Choisissez le dossier d’une version du jeu, comme _retail_.';

  @override
  String get issueDamagedFile =>
      'Un fichier enregistré n’a pas pu être lu, nous l’avons donc ignoré. Connectez-vous avec ce personnage, déconnectez-vous, puis réessayez.';

  @override
  String get issueAccountSkipped =>
      'Le fichier Memories d’un compte est absent ou endommagé, nous avons donc ignoré ses personnages. Connectez-vous une fois, déconnectez-vous, puis réessayez.';

  @override
  String get issueCharacterFailed =>
      'Nous n’avons pas pu mettre à jour les données d’un personnage et nous les avons laissées telles quelles. Vérifiez son dossier dans les dernières données, puis réessayez.';

  @override
  String get issueOverlap =>
      'Le dossier de sauvegarde se trouve dans les fichiers du jeu. Choisissez un dossier de sauvegarde en dehors du dossier World of Warcraft.';

  @override
  String get issueLockHeld =>
      'Une autre collecte est en cours sur ce dossier de sauvegarde. Attendez qu’elle se termine, puis réessayez.';

  @override
  String get issueNotWritable =>
      'Nous ne pouvons pas écrire dans le dossier de sauvegarde. Vérifiez que son disque est connecté et a de la place libre, ou choisissez un autre dossier de sauvegarde.';

  @override
  String get issueBadIndex =>
      'Le fichier index.json des dernières données est endommagé. Sortez-le du dossier, puis réessayez.';

  @override
  String get issueBadDefault =>
      'Le premier personnage à afficher n’est pas dans vos données. Réessayez.';

  @override
  String get issueSkippedFile =>
      'Un fichier enregistré ne contenait pas de données Memories ou appartenait à un autre personnage, nous l’avons donc ignoré.';

  @override
  String get issueDuplicateGuid =>
      'Deux dossiers contiennent le même personnage. Nous avons gardé celui que vous avez joué en dernier.';

  @override
  String get issueBackupFailed =>
      'Nous n’avons pas pu copier un fichier enregistré dans le dossier de sauvegarde. Vérifiez que son disque a de la place libre, puis réessayez.';

  @override
  String get issueScreenshotFailed =>
      'Nous n’avons pas pu copier une capture d’écran. Vérifiez que le disque a de la place libre, puis réessayez.';

  @override
  String get issueIoError =>
      'Un fichier n’a pas pu être lu ou écrit, la collecte s’est donc arrêtée. Vérifiez que vos disques sont connectés et ont de la place libre, puis réessayez.';

  @override
  String get fixChooseWowFolder => 'Choisir le dossier';

  @override
  String get fixChooseBackupFolder => 'Choisir le dossier de sauvegarde';

  @override
  String get fixOpenLatest => 'Ouvrir les dernières données';

  @override
  String get fixTryAgain => 'Réessayer';

  @override
  String get statusGathering => 'Collecte de votre parcours…';

  @override
  String get statusFailed =>
      'La dernière collecte ne s’est pas terminée. Voir le problème ci-dessous.';

  @override
  String statusDoneProblems(String when) {
    return 'Collecté avec des problèmes. Dernière collecte $when';
  }

  @override
  String statusDone(String when) {
    return 'À jour. Dernière collecte $when';
  }

  @override
  String statusIdleLast(String when) {
    return 'Dernière collecte $when';
  }

  @override
  String get statusNever => 'Jamais collecté';

  @override
  String statusSemantics(String status) {
    return 'État : $status';
  }

  @override
  String get gathering => 'Collecte…';

  @override
  String get gatheringSemantics => 'Collecte en cours, veuillez patienter';

  @override
  String get gatheringProgress => 'Collecte';

  @override
  String get gatherNow => 'Collecter maintenant';

  @override
  String get countCharacters => 'Personnages';

  @override
  String get countJournalLines => 'Lignes du journal';

  @override
  String get countScreenshots => 'Captures d’écran';

  @override
  String countSemantics(String label, int value) {
    return '$label : $value';
  }

  @override
  String get charactersTitle => 'Personnages';

  @override
  String get noCharacters =>
      'Aucun personnage pour l’instant. Cliquez sur Collecter maintenant.';

  @override
  String characterLevel(int level) {
    return 'Niveau $level';
  }

  @override
  String get backupFolderTitle => 'Dossier de sauvegarde';

  @override
  String get notSet => 'Non défini';

  @override
  String backupSize(String size) {
    return 'Taille : $size';
  }

  @override
  String get openBackupFolder => 'Ouvrir le dossier de sauvegarde';

  @override
  String get openLatestData => 'Ouvrir les dernières données';

  @override
  String get openFolderFailed =>
      'Nous n’avons pas pu ouvrir ce dossier. Si vous n’avez pas encore collecté, cliquez d’abord sur Collecter maintenant.';

  @override
  String get viewCharacter => 'Voir';

  @override
  String viewCharacterLabel(String name) {
    return 'Voir $name';
  }

  @override
  String get viewerStartFailed =>
      'Impossible de démarrer la visionneuse du parcours.';

  @override
  String get viewerOpenFailed =>
      'Impossible d’ouvrir le navigateur. Copiez le lien et ouvrez-le vous-même.';

  @override
  String get dismiss => 'Fermer';

  @override
  String get showWebsiteTab => 'Afficher l’onglet Site web';

  @override
  String andMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'et $count autres',
      one: 'et 1 autre',
    );
    return '$_temp0';
  }

  @override
  String sizeBytes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count octets',
      one: '$count octet',
    );
    return '$_temp0';
  }

  @override
  String sizeKb(String value) {
    return '$value Ko';
  }

  @override
  String sizeMb(String value) {
    return '$value Mo';
  }

  @override
  String sizeGb(String value) {
    return '$value Go';
  }

  @override
  String sizeTb(String value) {
    return '$value To';
  }

  @override
  String get classWarrior => 'Guerrier';

  @override
  String get classPaladin => 'Paladin';

  @override
  String get classHunter => 'Chasseur';

  @override
  String get classRogue => 'Voleur';

  @override
  String get classPriest => 'Prêtre';

  @override
  String get classDeathKnight => 'Chevalier de la mort';

  @override
  String get classShaman => 'Chaman';

  @override
  String get classMage => 'Mage';

  @override
  String get classWarlock => 'Démoniste';

  @override
  String get classMonk => 'Moine';

  @override
  String get classDruid => 'Druide';

  @override
  String get classDemonHunter => 'Chasseur de démons';

  @override
  String get classEvoker => 'Évocateur';

  @override
  String get settingsSaveFailed =>
      'Nous n’avons pas pu enregistrer vos réglages. Vérifiez que votre disque a de la place libre, puis modifiez à nouveau le réglage.';

  @override
  String get settingsDamaged =>
      'Votre fichier de réglages était endommagé, l’app a donc démarré avec les réglages par défaut. Vérifiez vos dossiers et vos interrupteurs.';

  @override
  String get wowFolderTitle => 'Dossier WoW';

  @override
  String get changeWowFolderSemantics => 'Changer le dossier WoW';

  @override
  String get changeBackupFolderSemantics => 'Changer le dossier de sauvegarde';

  @override
  String get change => 'Changer';

  @override
  String get watchTitle => 'Surveiller';

  @override
  String get watchSubtitle =>
      'Collecter automatiquement chaque fois que le jeu enregistre.';

  @override
  String get startAtLoginTitle => 'Lancer à l’ouverture de session';

  @override
  String get startAtLoginSubtitle =>
      'Lancer l’app masquée quand vous ouvrez votre session.';

  @override
  String get languageTitle => 'Langue';

  @override
  String get languageSystem => 'Système';

  @override
  String get versionTitle => 'Version';

  @override
  String versionText(String version, String core) {
    return 'WoW Journey $version, $core';
  }

  @override
  String get wizardTitle => 'Bienvenue dans WoW Journey';

  @override
  String wizardStep(int step, int total) {
    return 'Étape $step sur $total';
  }

  @override
  String get back => 'Retour';

  @override
  String backSemantics(int step) {
    return 'Retour à l’étape $step';
  }

  @override
  String get next => 'Suivant';

  @override
  String get nextSemantics => 'Étape suivante';

  @override
  String get finish => 'Terminer';

  @override
  String get finishSemantics => 'Terminer la configuration';

  @override
  String get wowStepTitle => 'Votre dossier WoW';

  @override
  String get wowStepIntro =>
      'Nous lisons les fichiers que les addons Memories enregistrent dans ce dossier. Nous ne les modifions jamais.';

  @override
  String get lookingForWow => 'Recherche de World of Warcraft…';

  @override
  String get noWowFound =>
      'Nous n’avons pas trouvé World of Warcraft. Choisissez le dossier d’une version du jeu, comme _retail_, dans votre dossier World of Warcraft.';

  @override
  String get chooseFolder => 'Choisir le dossier';

  @override
  String get chooseWowSemantics => 'Choisir le dossier WoW';

  @override
  String get noMemoriesYet => 'Aucune donnée Memories pour l’instant.';

  @override
  String wowFolderSemantics(String path) {
    return 'Dossier WoW : $path';
  }

  @override
  String get backupStepTitle => 'Votre dossier de sauvegarde';

  @override
  String get backupStepIntro =>
      'Nous gardons ici une copie de vos fichiers de jeu et de vos captures d’écran.';

  @override
  String backupFolderSemantics(String path) {
    return 'Dossier de sauvegarde : $path';
  }

  @override
  String get backupFolderSemanticsNotSet =>
      'Dossier de sauvegarde : non défini';

  @override
  String get chooseBackupPrompt => 'Choisissez un dossier de sauvegarde.';

  @override
  String get switchStepTitle => 'Fonctionnement de l’app';

  @override
  String get switchStepIntro =>
      'Vous pourrez modifier ces choix plus tard dans les Réglages.';

  @override
  String get useThisFolder => 'Utiliser ce dossier';

  @override
  String get pickerFailed =>
      'Nous n’avons pas pu ouvrir le sélecteur de dossier. Réessayez, ou redémarrez l’app.';

  @override
  String get checkFailed =>
      'Nous n’avons pas pu vérifier ce dossier. Réessayez, ou choisissez un autre dossier.';

  @override
  String get chooseGameVersion => 'Choisir une version du jeu';

  @override
  String get backupInsideWow =>
      'Ce dossier est dans votre dossier World of Warcraft, ou le contient. Choisissez un dossier de sauvegarde en dehors du dossier du jeu.';

  @override
  String get backupInsideWowFirst =>
      'Votre dossier de sauvegarde est dans ce dossier World of Warcraft, ou le contient. Choisissez d’abord un autre dossier de sauvegarde, puis ce dossier WoW.';

  @override
  String get useBackupTitle => 'Utiliser ce dossier de sauvegarde ?';

  @override
  String useBackupBody(String path) {
    return 'Les nouvelles collectes iront dans $path. Votre ancien dossier de sauvegarde reste tel quel. Nous ne le déplaçons pas et ne le supprimons pas.';
  }

  @override
  String get cancel => 'Annuler';

  @override
  String get flavorReady => 'Ce dossier WoW est prêt.';

  @override
  String get flavorReadyNoData =>
      'Ce dossier WoW est prêt, mais il n’a pas encore de données Memories. Jouez avec les addons Memories activés. Le jeu enregistre ses fichiers quand vous vous déconnectez ou tapez /reload.';

  @override
  String get flavorNoWtf =>
      'Ce dossier n’est pas un dossier de jeu WoW. Il n’a pas de dossier WTF/Account. Choisissez le dossier d’une version du jeu dans votre dossier World of Warcraft, comme _retail_.';

  @override
  String flavorInstallFolder(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Voici le dossier World of Warcraft. Il contient $count versions du jeu : $names. Choisissez-en une.',
      one:
          'Voici le dossier World of Warcraft. Il contient une version du jeu : $names. Choisissez ce dossier.',
    );
    return '$_temp0';
  }

  @override
  String get flavorNotADirectory =>
      'Ce n’est pas un dossier, ou il n’existe plus. Choisissez un dossier.';

  @override
  String get flavorNotReadable =>
      'Ce dossier, ou un dossier qu’il contient, ne peut pas être lu. Vérifiez que votre utilisateur peut l’ouvrir, puis choisissez-le à nouveau.';

  @override
  String get websiteTitle => 'Site web';

  @override
  String websiteCardTitle(String site) {
    return 'Site web : $site';
  }

  @override
  String get registrationTitle => 'Inscription';

  @override
  String get unlistedText =>
      'Les pages de vos personnages sont non listées : toute personne qui a le lien peut les ouvrir.';

  @override
  String get lostKeyText =>
      'Si vous réinstallez l’app ou créez une nouvelle clé, copiez votre nouvelle clé et demandez à l’administrateur du site de déplacer vos personnages vers elle.';

  @override
  String get websiteAddressLabel => 'Adresse du site web';

  @override
  String get checkSiteLabel => 'Vérifier';

  @override
  String get inviteCodeLabel => 'Code d’invitation';

  @override
  String get registerLabel => 'S’inscrire';

  @override
  String get uploadSwitchTitle => 'Envoi';

  @override
  String get uploadSwitchSubtitle =>
      'Envoyer votre parcours au site web après chaque collecte.';

  @override
  String get uploadNowLabel => 'Envoyer maintenant';

  @override
  String get uploadingLabel => 'Envoi…';

  @override
  String get uploadingSemantics => 'Envoi en cours, veuillez patienter';

  @override
  String get uploadPausedText =>
      'Envoi en pause. Il reprend après la prochaine collecte.';

  @override
  String get requestScreenshotsLabel => 'Demander les captures d’écran';

  @override
  String get copyLinkLabel => 'Copier le lien';

  @override
  String copyLinkSemantics(String name) {
    return 'Copier le lien de $name';
  }

  @override
  String get removeFromWebsiteLabel => 'Retirer du site web';

  @override
  String removeFromWebsiteSemantics(String name) {
    return 'Retirer $name du site web';
  }

  @override
  String get linkCopiedText => 'Lien copié';

  @override
  String get removeLabel => 'Retirer';

  @override
  String siteFoundOpen(String name) {
    return '$name trouvé. Tout le monde peut s’inscrire ici.';
  }

  @override
  String siteFoundInvite(String name) {
    return '$name trouvé. Pour vous inscrire, il vous faut un code d’invitation de l’administrateur du site.';
  }

  @override
  String get notAMemoriesSite =>
      'Cette adresse ne ressemble pas à un site web Memories. Vérifiez l’adresse.';

  @override
  String registeredText(String site) {
    return 'Inscrit sur $site.';
  }

  @override
  String notRegisteredText(String site) {
    return 'Non inscrit sur $site. Inscrivez-vous pour envoyer votre parcours.';
  }

  @override
  String fingerprintText(String fingerprint) {
    return 'Votre clé : $fingerprint';
  }

  @override
  String get copyKeyLabel => 'Copier votre clé';

  @override
  String get copyKeySemantics =>
      'Copier votre clé pour l’administrateur du site';

  @override
  String get keyCopiedText => 'Clé copiée';

  @override
  String get newKeyLabel => 'Créer une nouvelle clé';

  @override
  String get newKeyTitle => 'Créer une nouvelle clé ?';

  @override
  String newKeyQuestionText(String site) {
    return 'Faites-le seulement si le site web a bloqué ou refusé cette clé. L’app crée une nouvelle clé et garde une copie de l’ancienne. Vos personnages sur $site restent liés à l’ancienne clé. L’administrateur du site peut les déplacer vers la nouvelle clé. Inscrivez-vous ensuite à nouveau. Le site web peut demander un nouveau code d’invitation. L’app envoie à nouveau vos personnages sélectionnés. L’envoi reste désactivé jusqu’à ce que vous l’activiez.';
  }

  @override
  String get newKeyDoneText =>
      'Nouvelle clé créée. Inscrivez-vous à nouveau pour envoyer.';

  @override
  String get errKeyNotReplaced =>
      'L’app n’a pas pu créer de nouvelle clé, elle garde donc l’ancienne. Vérifiez que son dossier est accessible en écriture et a de la place libre, puis réessayez.';

  @override
  String get screenshotsNone =>
      'Les captures d’écran ne sont pas envoyées. Demandez à l’administrateur du site de les approuver.';

  @override
  String get screenshotsPending =>
      'En attente de l’approbation de vos captures d’écran par l’administrateur du site.';

  @override
  String get screenshotsApproved =>
      'Vos captures d’écran sont envoyées avec votre parcours.';

  @override
  String get screenshotsDenied =>
      'L’administrateur du site n’a pas approuvé les captures d’écran. Vous pouvez demander à nouveau.';

  @override
  String cardNotRegistered(String site) {
    return 'Vous n’êtes pas inscrit sur $site. Inscrivez-vous ci-dessous pour partager votre parcours.';
  }

  @override
  String get cardUploadOff =>
      'L’envoi est désactivé. Activez l’interrupteur Envoi ci-dessous pour envoyer votre parcours.';

  @override
  String get selectionTitle => 'Personnages à envoyer';

  @override
  String get selectionHint => 'Choisissez les personnages à envoyer.';

  @override
  String get selectionNote =>
      'Les nouveaux personnages ne sont pas envoyés tant que vous ne les cochez pas. Décocher un personnage arrête seulement les envois suivants ; rien n’est retiré du site web.';

  @override
  String get selectAllLabel => 'Tout sélectionner';

  @override
  String get selectNoneLabel => 'Ne rien sélectionner';

  @override
  String uploadProgress(int done, int total) {
    return 'Envoi $done sur $total';
  }

  @override
  String get lastUploadNever => 'Rien n’a encore été envoyé.';

  @override
  String lastUpload(String time) {
    return 'Dernier envoi $time';
  }

  @override
  String syncUploaded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count personnages envoyés',
      one: '1 personnage envoyé',
    );
    return '$_temp0';
  }

  @override
  String syncShots(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count captures d’écran envoyées',
      one: '1 capture d’écran envoyée',
    );
    return '$_temp0';
  }

  @override
  String get syncUpToDate => 'tout est à jour';

  @override
  String syncFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count personnages en échec',
      one: '1 personnage en échec',
    );
    return '$_temp0';
  }

  @override
  String syncShotsFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count captures d’écran en échec',
      one: '1 capture d’écran en échec',
    );
    return '$_temp0';
  }

  @override
  String errNetwork(String host) {
    return 'Impossible de joindre $host. Vérifiez la connexion internet et l’adresse du site web.';
  }

  @override
  String get errBadResponse =>
      'Le site web a envoyé une réponse que ce programme ne comprend pas. Vérifiez l’adresse du site web.';

  @override
  String get errBadFiles =>
      'Un fichier de votre parcours est absent ou illisible, il n’a donc pas été envoyé. Collectez à nouveau, puis réessayez.';

  @override
  String get errNoIndex =>
      'Impossible de lire index.json des dernières données. Lancez d’abord la collecte, puis réessayez.';

  @override
  String get errBadKey =>
      'Le fichier de clé de l’app ne peut pas être lu ou écrit. Vérifiez ses droits et la place libre de son dossier.';

  @override
  String get errBadSite =>
      'L’adresse du site web n’est pas valide. Écrivez-la ainsi : https://example.com.';

  @override
  String get errBadState =>
      'L’application n’a pas pu enregistrer votre choix de personnages à envoyer. Vérifiez que l’on peut écrire dans le dossier de l’application, puis réessayez.';

  @override
  String get errFailed =>
      'L’envoi s’est arrêté à cause d’un problème dans l’app. Réessayez après la prochaine collecte.';

  @override
  String errHttp(String status) {
    return 'Le site web a répondu avec le statut $status. Réessayez plus tard et vérifiez l’adresse du site web.';
  }

  @override
  String errKeyRevoked(String site) {
    return 'L’administrateur du site web a bloqué la clé de cette app. Les envois vers $site sont désactivés.';
  }

  @override
  String get errNotRegistered =>
      'Le site web ne connaît pas encore la clé de cette app. Inscrivez-vous dans l’onglet Site web.';

  @override
  String errClaimed(String name, String realm) {
    return 'Un autre joueur a déjà envoyé $name sur $realm. Demandez à l’administrateur du site web.';
  }

  @override
  String get realmUnknown => 'son royaume';

  @override
  String get errInvalid =>
      'Le site web n’a pas accepté les données. Corrigez les fichiers enregistrés, puis envoyez à nouveau.';

  @override
  String get errInviteInvalid =>
      'Le code d’invitation n’est pas valide. Demandez-en un nouveau à l’administrateur du site web.';

  @override
  String get errBadSignature =>
      'Le site web n’a pas accepté la signature de l’app. Vérifiez que l’horloge de votre ordinateur est juste, puis réessayez.';

  @override
  String get errRateLimited =>
      'Trop de requêtes. Attendez une minute, puis réessayez.';

  @override
  String get errBusy =>
      'Le site web est occupé par d’autres envois. Réessayez dans quelques minutes.';

  @override
  String get errQuota =>
      'Le site web n’a plus de place pour vos données. Demandez à l’administrateur du site web.';

  @override
  String get errTooLarge =>
      'Vos données sont trop volumineuses pour ce site web. Demandez à l’administrateur du site web d’augmenter la limite.';

  @override
  String get errInternal =>
      'Le site web a rencontré un problème. Réessayez dans quelques minutes.';

  @override
  String get errBadRequest =>
      'Le site web n’a pas pu lire la requête. Réessayez, et mettez l’app à jour si cela continue.';

  @override
  String get errNotFound =>
      'Ce site web n’a aucun personnage de ce nom pour cette clé.';

  @override
  String get errScreenshotsNotApproved =>
      'L’administrateur du site web n’a pas encore approuvé vos captures d’écran.';

  @override
  String get errUnsupportedImage =>
      'Le site web n’a pas accepté une capture d’écran, car son type d’image n’est pas pris en charge.';

  @override
  String get errNotReferenced =>
      'Une capture d’écran n’appartient à aucune ligne du journal, le site web ne l’a donc pas gardée.';

  @override
  String get errGuidMismatch =>
      'Ce nom de personnage appartient déjà à un autre personnage sur le site web. Demandez à l’administrateur du site web.';

  @override
  String get errGzipRequired =>
      'L’envoi n’était pas compressé comme le site web l’exige. Mettez l’app à jour, puis réessayez.';

  @override
  String namedError(String name, String text) {
    return '$name : $text';
  }

  @override
  String rejectedText(String name, String problems, int more) {
    String _temp0 = intl.Intl.pluralLogic(
      more,
      locale: localeName,
      other: ' Et $more autres problèmes.',
      one: ' Et 1 autre problème.',
      zero: '',
    );
    return 'Le site web n’a pas accepté les données de $name : $problems$_temp0 Corrigez les fichiers enregistrés, puis envoyez à nouveau.';
  }

  @override
  String get siteInvalid =>
      'L’adresse du site web n’est pas valide. Écrivez-la ainsi : https://example.com.';

  @override
  String get siteNeedsHost =>
      'L’adresse du site web doit avoir un schéma et un hôte, comme https://example.com.';

  @override
  String get siteNeedsHttps =>
      'L’adresse du site web doit commencer par https://.';

  @override
  String get siteHttpLoopback =>
      'L’adresse du site web doit commencer par https://. Le http:// simple n’est autorisé que pour localhost, 127.0.0.1 et [::1].';

  @override
  String get siteUserInfo =>
      'L’adresse du site web ne peut pas contenir de nom d’utilisateur ni de mot de passe.';

  @override
  String get siteQuery =>
      'L’adresse du site web ne peut pas contenir de requête ni de fragment.';

  @override
  String get sitePath =>
      'L’adresse du site web ne peut pas contenir de chemin. Utilisez l’adresse du site lui-même, comme https://example.com.';

  @override
  String removeQuestionText(String name, String site) {
    return 'Retirer $name de $site ? La page et ses données sont supprimées.';
  }

  @override
  String removedText(String name) {
    return '$name a été retiré du site web et décoché. Cochez-le à nouveau pour l’envoyer.';
  }

  @override
  String get busyText =>
      'L’app est occupée avec le site web. Réessayez quand l’envoi se termine.';

  @override
  String get genericFailureText =>
      'Un problème est survenu avec le site web. Réessayez dans quelques minutes.';

  @override
  String get notAnswering =>
      'WoW Journey est déjà en cours d’exécution, mais n’a pas répondu. Quittez-le depuis le menu de son icône de la zone de notification, ou terminez-le dans le gestionnaire de tâches, puis relancez-le.';

  @override
  String get close => 'Fermer';

  @override
  String get trayGatherNow => 'Collecter maintenant';

  @override
  String get trayViewJourney => 'Voir le parcours';

  @override
  String get trayOpenWindow => 'Ouvrir la fenêtre';

  @override
  String get trayOpenBackupFolder => 'Ouvrir le dossier de sauvegarde';

  @override
  String get trayQuit => 'Quitter';
}
