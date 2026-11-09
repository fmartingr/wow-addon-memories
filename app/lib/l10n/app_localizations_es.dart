// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'WoW Journey';

  @override
  String get loadingSettings => 'Cargando tu configuración';

  @override
  String get tabOverview => 'Resumen';

  @override
  String get tabWebsite => 'Sitio web';

  @override
  String get tabSettings => 'Ajustes';

  @override
  String get noDataText =>
      'Aún no hay datos de Memories. Juega con los addons de Memories activados y luego cierra la sesión.';

  @override
  String get wowFolderGoneText =>
      'Ya no encontramos tu carpeta de WoW. Puede que se haya movido, o que su unidad no esté conectada. Elige la carpeta de nuevo.';

  @override
  String get saveHintText =>
      'El juego guarda tu viaje cuando cierras la sesión o escribes /reload.';

  @override
  String get watchingText => 'Vigilando cambios';

  @override
  String get issueNoWtf =>
      'Esta carpeta no tiene archivos del juego de WoW. Elige la carpeta de una versión del juego, como _retail_.';

  @override
  String get issueDamagedFile =>
      'No se pudo leer un archivo guardado, así que lo omitimos. Entra con ese personaje, cierra la sesión y vuelve a intentarlo.';

  @override
  String get issueAccountSkipped =>
      'Falta el archivo de Memories de una cuenta o está dañado, así que omitimos sus personajes. Entra una vez, cierra la sesión y vuelve a intentarlo.';

  @override
  String get issueCharacterFailed =>
      'No pudimos actualizar los datos de un personaje y los dejamos como estaban. Revisa su carpeta en los últimos datos y vuelve a intentarlo.';

  @override
  String get issueOverlap =>
      'La carpeta de copias está dentro de los archivos del juego. Elige una carpeta de copias fuera de la carpeta de World of Warcraft.';

  @override
  String get issueLockHeld =>
      'Otra recopilación se está ejecutando en esta carpeta de copias. Espera a que termine y vuelve a intentarlo.';

  @override
  String get issueNotWritable =>
      'No podemos escribir en la carpeta de copias. Comprueba que su unidad esté conectada y tenga espacio libre, o elige otra carpeta de copias.';

  @override
  String get issueBadIndex =>
      'El archivo index.json de los últimos datos está dañado. Sácalo de la carpeta y vuelve a intentarlo.';

  @override
  String get issueBadDefault =>
      'El primer personaje que mostrar no está en tus datos. Vuelve a intentarlo.';

  @override
  String get issueSkippedFile =>
      'Un archivo guardado no tenía datos de Memories o pertenecía a otro personaje, así que lo omitimos.';

  @override
  String get issueDuplicateGuid =>
      'Dos carpetas contienen el mismo personaje. Conservamos la que jugaste por última vez.';

  @override
  String get issueBackupFailed =>
      'No pudimos copiar un archivo guardado en la carpeta de copias. Comprueba que su unidad tenga espacio libre y vuelve a intentarlo.';

  @override
  String get issueScreenshotFailed =>
      'No pudimos copiar una captura de pantalla. Comprueba que la unidad tenga espacio libre y vuelve a intentarlo.';

  @override
  String get issueIoError =>
      'No se pudo leer o escribir un archivo, así que la recopilación se detuvo. Comprueba que tus unidades estén conectadas y tengan espacio libre, y vuelve a intentarlo.';

  @override
  String get fixChooseWowFolder => 'Elegir carpeta';

  @override
  String get fixChooseBackupFolder => 'Elegir carpeta de copias';

  @override
  String get fixOpenLatest => 'Abrir los últimos datos';

  @override
  String get fixTryAgain => 'Reintentar';

  @override
  String get statusGathering => 'Recopilando tu viaje…';

  @override
  String get statusFailed =>
      'La última recopilación no terminó. Mira el problema de abajo.';

  @override
  String statusDoneProblems(String when) {
    return 'Recopilado con problemas. Última recopilación $when';
  }

  @override
  String statusDone(String when) {
    return 'Al día. Última recopilación $when';
  }

  @override
  String statusIdleLast(String when) {
    return 'Última recopilación $when';
  }

  @override
  String get statusNever => 'Nunca recopilado';

  @override
  String statusSemantics(String status) {
    return 'Estado: $status';
  }

  @override
  String get gathering => 'Recopilando…';

  @override
  String get gatheringSemantics => 'Recopilando, espera por favor';

  @override
  String get gatheringProgress => 'Recopilando';

  @override
  String get gatherNow => 'Recopilar ahora';

  @override
  String get countCharacters => 'Personajes';

  @override
  String get countJournalLines => 'Líneas del diario';

  @override
  String get countScreenshots => 'Capturas';

  @override
  String countSemantics(String label, int value) {
    return '$label: $value';
  }

  @override
  String get charactersTitle => 'Personajes';

  @override
  String get noCharacters => 'Aún no hay personajes. Pulsa Recopilar ahora.';

  @override
  String characterLevel(int level) {
    return 'Nivel $level';
  }

  @override
  String get backupFolderTitle => 'Carpeta de copias';

  @override
  String get notSet => 'Sin definir';

  @override
  String backupSize(String size) {
    return 'Tamaño: $size';
  }

  @override
  String get openBackupFolder => 'Abrir carpeta de copias';

  @override
  String get openLatestData => 'Abrir los últimos datos';

  @override
  String get openFolderFailed =>
      'No pudimos abrir esta carpeta. Si aún no has recopilado, pulsa primero Recopilar ahora.';

  @override
  String get dismiss => 'Cerrar';

  @override
  String get showWebsiteTab => 'Mostrar la pestaña Sitio web';

  @override
  String andMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'y $count más',
      one: 'y 1 más',
    );
    return '$_temp0';
  }

  @override
  String sizeBytes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bytes',
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
  String get classWarrior => 'Guerrero';

  @override
  String get classPaladin => 'Paladín';

  @override
  String get classHunter => 'Cazador';

  @override
  String get classRogue => 'Pícaro';

  @override
  String get classPriest => 'Sacerdote';

  @override
  String get classDeathKnight => 'Caballero de la Muerte';

  @override
  String get classShaman => 'Chamán';

  @override
  String get classMage => 'Mago';

  @override
  String get classWarlock => 'Brujo';

  @override
  String get classMonk => 'Monje';

  @override
  String get classDruid => 'Druida';

  @override
  String get classDemonHunter => 'Cazador de demonios';

  @override
  String get classEvoker => 'Evocador';

  @override
  String get settingsSaveFailed =>
      'No pudimos guardar tus ajustes. Comprueba que tu disco tenga espacio libre y cambia el ajuste de nuevo.';

  @override
  String get settingsDamaged =>
      'Tu archivo de ajustes estaba dañado, así que la app arrancó con los ajustes por defecto. Revisa tus carpetas y tus interruptores.';

  @override
  String get wowFolderTitle => 'Carpeta de WoW';

  @override
  String get changeWowFolderSemantics => 'Cambiar la carpeta de WoW';

  @override
  String get changeBackupFolderSemantics => 'Cambiar la carpeta de copias';

  @override
  String get change => 'Cambiar';

  @override
  String get watchTitle => 'Vigilar';

  @override
  String get watchSubtitle => 'Recopilar solo cada vez que el juego guarda.';

  @override
  String get startAtLoginTitle => 'Iniciar al entrar';

  @override
  String get startAtLoginSubtitle =>
      'Iniciar la app oculta cuando inicies sesión.';

  @override
  String get languageTitle => 'Idioma';

  @override
  String get languageSystem => 'Sistema';

  @override
  String get versionTitle => 'Versión';

  @override
  String versionText(String version, String core) {
    return 'WoW Journey $version, $core';
  }

  @override
  String get wizardTitle => 'Te damos la bienvenida a WoW Journey';

  @override
  String wizardStep(int step, int total) {
    return 'Paso $step de $total';
  }

  @override
  String get back => 'Atrás';

  @override
  String backSemantics(int step) {
    return 'Volver al paso $step';
  }

  @override
  String get next => 'Siguiente';

  @override
  String get nextSemantics => 'Paso siguiente';

  @override
  String get finish => 'Terminar';

  @override
  String get finishSemantics => 'Terminar la configuración';

  @override
  String get wowStepTitle => 'Tu carpeta de WoW';

  @override
  String get wowStepIntro =>
      'Leemos los archivos que los addons de Memories guardan en esta carpeta. Nunca los modificamos.';

  @override
  String get lookingForWow => 'Buscando World of Warcraft…';

  @override
  String get noWowFound =>
      'No pudimos encontrar World of Warcraft. Elige la carpeta de una versión del juego, como _retail_, dentro de tu carpeta de World of Warcraft.';

  @override
  String get chooseFolder => 'Elegir carpeta';

  @override
  String get chooseWowSemantics => 'Elegir la carpeta de WoW';

  @override
  String get noMemoriesYet => 'Aún no hay datos de Memories.';

  @override
  String wowFolderSemantics(String path) {
    return 'Carpeta de WoW: $path';
  }

  @override
  String get backupStepTitle => 'Tu carpeta de copias';

  @override
  String get backupStepIntro =>
      'Aquí guardamos una copia de tus archivos del juego y de tus capturas.';

  @override
  String backupFolderSemantics(String path) {
    return 'Carpeta de copias: $path';
  }

  @override
  String get backupFolderSemanticsNotSet => 'Carpeta de copias: sin definir';

  @override
  String get chooseBackupPrompt => 'Elige una carpeta de copias.';

  @override
  String get switchStepTitle => 'Cómo funciona la app';

  @override
  String get switchStepIntro => 'Puedes cambiar esto más tarde en Ajustes.';

  @override
  String get useThisFolder => 'Usar esta carpeta';

  @override
  String get pickerFailed =>
      'No pudimos abrir el selector de carpetas. Vuelve a intentarlo o reinicia la app.';

  @override
  String get checkFailed =>
      'No pudimos comprobar esta carpeta. Vuelve a intentarlo o elige otra carpeta.';

  @override
  String get chooseGameVersion => 'Elige una versión del juego';

  @override
  String get backupInsideWow =>
      'Esta carpeta está dentro de tu carpeta de World of Warcraft, o la contiene. Elige una carpeta de copias fuera de la carpeta del juego.';

  @override
  String get backupInsideWowFirst =>
      'Tu carpeta de copias está dentro de esta carpeta de World of Warcraft, o la contiene. Elige primero otra carpeta de copias y después esta carpeta de WoW.';

  @override
  String get useBackupTitle => '¿Usar esta carpeta de copias?';

  @override
  String useBackupBody(String path) {
    return 'Las nuevas recopilaciones irán a $path. Tu carpeta de copias anterior se queda como está. No la movemos ni la borramos.';
  }

  @override
  String get cancel => 'Cancelar';

  @override
  String get flavorReady => 'Esta carpeta de WoW está lista.';

  @override
  String get flavorReadyNoData =>
      'Esta carpeta de WoW está lista, pero aún no tiene datos de Memories. Juega con los addons de Memories activados. El juego guarda sus archivos cuando cierras la sesión o escribes /reload.';

  @override
  String get flavorNoWtf =>
      'Esta carpeta no es una carpeta de juego de WoW. No tiene carpeta WTF/Account. Elige la carpeta de una versión del juego dentro de tu carpeta de World of Warcraft, como _retail_.';

  @override
  String flavorInstallFolder(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Esta es la carpeta de World of Warcraft. Contiene $count versiones del juego: $names. Elige una de ellas.',
      one:
          'Esta es la carpeta de World of Warcraft. Contiene una versión del juego: $names. Elige esa carpeta.',
    );
    return '$_temp0';
  }

  @override
  String get flavorNotADirectory =>
      'Esto no es una carpeta, o ya no existe. Elige una carpeta.';

  @override
  String get flavorNotReadable =>
      'Esta carpeta, o una carpeta dentro de ella, no se puede leer. Comprueba que tu usuario pueda abrirla y vuelve a elegirla.';

  @override
  String get websiteTitle => 'Sitio web';

  @override
  String websiteCardTitle(String site) {
    return 'Sitio web: $site';
  }

  @override
  String get registrationTitle => 'Registro';

  @override
  String get unlistedText =>
      'Las páginas de tus personajes no están listadas: cualquiera que tenga el enlace puede abrirlas.';

  @override
  String get lostKeyText =>
      'Si reinstalas la app o creas una clave nueva, copia tu clave nueva y pide al administrador del sitio web que mueva tus personajes a ella.';

  @override
  String get websiteAddressLabel => 'Dirección del sitio web';

  @override
  String get checkSiteLabel => 'Comprobar';

  @override
  String get inviteCodeLabel => 'Código de invitación';

  @override
  String get registerLabel => 'Registrarse';

  @override
  String get uploadSwitchTitle => 'Subida';

  @override
  String get uploadSwitchSubtitle =>
      'Enviar tu viaje al sitio web después de cada recopilación.';

  @override
  String get uploadNowLabel => 'Subir ahora';

  @override
  String get uploadingLabel => 'Subiendo…';

  @override
  String get uploadingSemantics => 'Subiendo, espera por favor';

  @override
  String get uploadPausedText =>
      'Subida en pausa. Continúa después de la próxima recopilación.';

  @override
  String get requestScreenshotsLabel => 'Solicitar capturas';

  @override
  String get copyLinkLabel => 'Copiar enlace';

  @override
  String copyLinkSemantics(String name) {
    return 'Copiar el enlace de $name';
  }

  @override
  String get removeFromWebsiteLabel => 'Quitar del sitio web';

  @override
  String removeFromWebsiteSemantics(String name) {
    return 'Quitar a $name del sitio web';
  }

  @override
  String get linkCopiedText => 'Enlace copiado';

  @override
  String get removeLabel => 'Quitar';

  @override
  String siteFoundOpen(String name) {
    return 'Se encontró $name. Aquí puede registrarse cualquiera.';
  }

  @override
  String siteFoundInvite(String name) {
    return 'Se encontró $name. Para registrarte necesitas un código de invitación del administrador del sitio web.';
  }

  @override
  String get notAMemoriesSite =>
      'Esta dirección no parece un sitio web de Memories. Revisa la dirección.';

  @override
  String registeredText(String site) {
    return 'Registrado en $site.';
  }

  @override
  String notRegisteredText(String site) {
    return 'No registrado en $site. Regístrate para subir tu viaje.';
  }

  @override
  String fingerprintText(String fingerprint) {
    return 'Tu clave: $fingerprint';
  }

  @override
  String get copyKeyLabel => 'Copiar tu clave';

  @override
  String get copyKeySemantics =>
      'Copiar tu clave para el administrador del sitio web';

  @override
  String get keyCopiedText => 'Clave copiada';

  @override
  String get newKeyLabel => 'Crear una clave nueva';

  @override
  String get newKeyTitle => '¿Crear una clave nueva?';

  @override
  String newKeyQuestionText(String site) {
    return 'Hazlo solo cuando el sitio web haya bloqueado o rechazado esta clave. La app crea una clave nueva y guarda una copia de la antigua. Tus personajes en $site se quedan con la clave antigua. El administrador del sitio web puede moverlos a la clave nueva. Después, regístrate de nuevo. El sitio web puede pedir un código de invitación nuevo. La app vuelve a subir todos tus personajes. La subida sigue desactivada hasta que la actives.';
  }

  @override
  String get newKeyDoneText =>
      'Clave nueva creada. Regístrate de nuevo para subir.';

  @override
  String get errKeyNotReplaced =>
      'La app no pudo crear una clave nueva, así que conserva la antigua. Comprueba que se puede escribir en su carpeta y que tiene espacio libre, y vuelve a intentarlo.';

  @override
  String get screenshotsNone =>
      'Las capturas no se suben. Pide al administrador del sitio web que las apruebe.';

  @override
  String get screenshotsPending =>
      'Esperando a que el administrador del sitio web apruebe tus capturas.';

  @override
  String get screenshotsApproved => 'Tus capturas se suben con tu viaje.';

  @override
  String get screenshotsDenied =>
      'El administrador del sitio web no aprobó las capturas. Puedes volver a pedirlo.';

  @override
  String cardNotRegistered(String site) {
    return 'No estás registrado en $site. Regístrate abajo para compartir tu viaje.';
  }

  @override
  String get cardUploadOff =>
      'La subida está desactivada. Activa el interruptor Subida de abajo para enviar tu viaje.';

  @override
  String uploadProgress(int done, int total) {
    return 'Subiendo $done de $total';
  }

  @override
  String get lastUploadNever => 'Aún no se ha subido nada.';

  @override
  String lastUpload(String time) {
    return 'Última subida $time';
  }

  @override
  String syncUploaded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count personajes subidos',
      one: '1 personaje subido',
    );
    return '$_temp0';
  }

  @override
  String syncShots(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count capturas enviadas',
      one: '1 captura enviada',
    );
    return '$_temp0';
  }

  @override
  String get syncUpToDate => 'todo está al día';

  @override
  String syncRemoved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count personajes quitados omitidos (Subir ahora los envía de nuevo)',
      one: '1 personaje quitado omitido (Subir ahora lo envía de nuevo)',
    );
    return '$_temp0';
  }

  @override
  String syncFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count personajes fallaron',
      one: '1 personaje falló',
    );
    return '$_temp0';
  }

  @override
  String syncShotsFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count capturas fallaron',
      one: '1 captura falló',
    );
    return '$_temp0';
  }

  @override
  String errNetwork(String host) {
    return 'No se pudo conectar con $host. Comprueba la conexión a internet y la dirección del sitio web.';
  }

  @override
  String get errBadResponse =>
      'El sitio web envió una respuesta que este programa no entiende. Revisa la dirección del sitio web.';

  @override
  String get errBadFiles =>
      'Falta un archivo de tu viaje o no se puede leer, así que no se subió. Recopila de nuevo y vuelve a intentarlo.';

  @override
  String get errNoIndex =>
      'No se pudo leer index.json de los últimos datos. Ejecuta primero la recopilación y vuelve a intentarlo.';

  @override
  String get errBadKey =>
      'El archivo de clave de la app no se puede leer ni escribir. Revisa sus permisos y el espacio libre de su carpeta.';

  @override
  String get errBadSite =>
      'La dirección del sitio web no es válida. Escríbela así: https://example.com.';

  @override
  String get errBadState =>
      'El personaje se quitó del sitio web, pero la app no pudo guardarlo, así que la próxima recopilación puede subirlo de nuevo. Comprueba que se pueda escribir en la carpeta de la app.';

  @override
  String get errFailed =>
      'La subida se detuvo por un problema dentro de la app. Vuelve a intentarlo después de la próxima recopilación.';

  @override
  String errHttp(String status) {
    return 'El sitio web respondió con el estado $status. Vuelve a intentarlo más tarde y revisa la dirección del sitio web.';
  }

  @override
  String errKeyRevoked(String site) {
    return 'El administrador del sitio web bloqueó la clave de esta app. Las subidas a $site están desactivadas.';
  }

  @override
  String get errNotRegistered =>
      'El sitio web aún no conoce la clave de esta app. Regístrate en la pestaña Sitio web.';

  @override
  String errClaimed(String name, String realm) {
    return 'Otro jugador ya subió a $name en $realm. Pregunta al administrador del sitio web.';
  }

  @override
  String get realmUnknown => 'su reino';

  @override
  String get errInvalid =>
      'El sitio web no aceptó los datos. Corrige los archivos guardados y vuelve a subir.';

  @override
  String get errInviteInvalid =>
      'El código de invitación no es válido. Pide uno nuevo al administrador del sitio web.';

  @override
  String get errBadSignature =>
      'El sitio web no aceptó la firma de la app. Comprueba que el reloj de tu ordenador esté bien y vuelve a intentarlo.';

  @override
  String get errRateLimited =>
      'Demasiadas solicitudes. Espera un minuto y vuelve a intentarlo.';

  @override
  String get errBusy =>
      'El sitio web está ocupado con otras subidas. Vuelve a intentarlo en unos minutos.';

  @override
  String get errQuota =>
      'El sitio web ya no tiene espacio para tus datos. Pregunta al administrador del sitio web.';

  @override
  String get errTooLarge =>
      'Tus datos son demasiado grandes para este sitio web. Pide al administrador del sitio web que suba el límite.';

  @override
  String get errInternal =>
      'El sitio web tuvo un problema. Vuelve a intentarlo en unos minutos.';

  @override
  String get errBadRequest =>
      'El sitio web no pudo leer la solicitud. Vuelve a intentarlo y actualiza la app si sigue pasando.';

  @override
  String get errNotFound =>
      'Este sitio web no tiene ese personaje para esta clave.';

  @override
  String get errScreenshotsNotApproved =>
      'El administrador del sitio web aún no ha aprobado tus capturas.';

  @override
  String get errUnsupportedImage =>
      'El sitio web no aceptó una captura porque su tipo de imagen no es compatible.';

  @override
  String get errNotReferenced =>
      'Una captura no pertenece a ninguna línea del diario, así que el sitio web no la conservó.';

  @override
  String get errGuidMismatch =>
      'Este nombre de personaje ya pertenece a otro personaje en el sitio web. Pregunta al administrador del sitio web.';

  @override
  String get errGzipRequired =>
      'La subida no estaba comprimida como necesita el sitio web. Actualiza la app y vuelve a intentarlo.';

  @override
  String namedError(String name, String text) {
    return '$name: $text';
  }

  @override
  String rejectedText(String name, String problems, int more) {
    String _temp0 = intl.Intl.pluralLogic(
      more,
      locale: localeName,
      other: ' Y $more problemas más.',
      one: ' Y 1 problema más.',
      zero: '',
    );
    return 'El sitio web no aceptó los datos de $name: $problems$_temp0 Corrige los archivos guardados y vuelve a subir.';
  }

  @override
  String get siteInvalid =>
      'La dirección del sitio web no es válida. Escríbela así: https://example.com.';

  @override
  String get siteNeedsHost =>
      'La dirección del sitio web necesita un esquema y un host, como https://example.com.';

  @override
  String get siteNeedsHttps =>
      'La dirección del sitio web debe empezar por https://.';

  @override
  String get siteHttpLoopback =>
      'La dirección del sitio web debe empezar por https://. El http:// simple solo se permite para localhost, 127.0.0.1 y [::1].';

  @override
  String get siteUserInfo =>
      'La dirección del sitio web no puede contener un nombre de usuario ni una contraseña.';

  @override
  String get siteQuery =>
      'La dirección del sitio web no puede contener una consulta ni un fragmento.';

  @override
  String get sitePath =>
      'La dirección del sitio web no puede contener una ruta. Usa la dirección del propio sitio, como https://example.com.';

  @override
  String removeQuestionText(String name, String site) {
    return '¿Quitar a $name de $site? La página y sus datos se borran.';
  }

  @override
  String removedText(String name) {
    return '$name se quitó del sitio web. Las recopilaciones no lo suben de nuevo; Subir ahora sí.';
  }

  @override
  String get busyText =>
      'La app está ocupada con el sitio web. Vuelve a intentarlo cuando termine la subida.';

  @override
  String get genericFailureText =>
      'Algo salió mal con el sitio web. Vuelve a intentarlo en unos minutos.';

  @override
  String get notAnswering =>
      'WoW Journey ya se está ejecutando, pero no respondió. Usa Salir en el menú de su icono de la bandeja, o finalízalo en el administrador de tareas, y vuelve a iniciarlo.';

  @override
  String get close => 'Cerrar';

  @override
  String get trayGatherNow => 'Recopilar ahora';

  @override
  String get trayOpenWindow => 'Abrir ventana';

  @override
  String get trayOpenBackupFolder => 'Abrir carpeta de copias';

  @override
  String get trayQuit => 'Salir';
}
