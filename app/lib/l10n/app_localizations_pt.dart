// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appTitle => 'WoW Journey';

  @override
  String get loadingSettings => 'Carregando suas configurações';

  @override
  String get tabOverview => 'Visão geral';

  @override
  String get tabWebsite => 'Site';

  @override
  String get tabSettings => 'Configurações';

  @override
  String get noDataText =>
      'Ainda não há dados do Memories. Jogue com os addons do Memories ativados e depois saia do jogo.';

  @override
  String get wowFolderGoneText =>
      'Não encontramos mais a sua pasta do WoW. Ela pode ter sido movida, ou o drive dela não está conectado. Escolha a pasta de novo.';

  @override
  String get saveHintText =>
      'O jogo salva a sua jornada quando você sai ou digita /reload.';

  @override
  String get watchingText => 'Monitorando alterações';

  @override
  String get issueNoWtf =>
      'Esta pasta não tem arquivos do jogo WoW. Escolha a pasta de uma versão do jogo, como _retail_.';

  @override
  String get issueDamagedFile =>
      'Não foi possível ler um arquivo salvo, então o ignoramos. Entre com esse personagem, saia e tente de novo.';

  @override
  String get issueAccountSkipped =>
      'O arquivo do Memories de uma conta está ausente ou danificado, então ignoramos os personagens dela. Entre uma vez, saia e tente de novo.';

  @override
  String get issueCharacterFailed =>
      'Não conseguimos atualizar os dados de um personagem e os deixamos como estavam. Confira a pasta dele nos dados mais recentes e tente de novo.';

  @override
  String get issueOverlap =>
      'A pasta de backup está dentro dos arquivos do jogo. Escolha uma pasta de backup fora da pasta do World of Warcraft.';

  @override
  String get issueLockHeld =>
      'Outra coleta está em andamento nesta pasta de backup. Espere ela terminar e tente de novo.';

  @override
  String get issueNotWritable =>
      'Não conseguimos gravar na pasta de backup. Confira se o drive dela está conectado e tem espaço livre, ou escolha outra pasta de backup.';

  @override
  String get issueBadIndex =>
      'O arquivo index.json dos dados mais recentes está danificado. Tire-o da pasta e tente de novo.';

  @override
  String get issueBadDefault =>
      'O primeiro personagem a mostrar não está nos seus dados. Tente de novo.';

  @override
  String get issueSkippedFile =>
      'Um arquivo salvo não tinha dados do Memories ou era de outro personagem, então o ignoramos.';

  @override
  String get issueDuplicateGuid =>
      'Duas pastas têm o mesmo personagem. Mantivemos a que você jogou por último.';

  @override
  String get issueBackupFailed =>
      'Não conseguimos copiar um arquivo salvo para a pasta de backup. Confira se o drive dela tem espaço livre e tente de novo.';

  @override
  String get issueScreenshotFailed =>
      'Não conseguimos copiar uma captura de tela. Confira se o drive tem espaço livre e tente de novo.';

  @override
  String get issueIoError =>
      'Não foi possível ler ou gravar um arquivo, então a coleta parou. Confira se os seus drives estão conectados e têm espaço livre e tente de novo.';

  @override
  String get fixChooseWowFolder => 'Escolher pasta';

  @override
  String get fixChooseBackupFolder => 'Escolher pasta de backup';

  @override
  String get fixOpenLatest => 'Abrir dados mais recentes';

  @override
  String get fixTryAgain => 'Tentar de novo';

  @override
  String get statusGathering => 'Coletando a sua jornada…';

  @override
  String get statusFailed =>
      'A última coleta não terminou. Veja o problema abaixo.';

  @override
  String statusDoneProblems(String when) {
    return 'Coletado com problemas. Última coleta $when';
  }

  @override
  String statusDone(String when) {
    return 'Em dia. Última coleta $when';
  }

  @override
  String statusIdleLast(String when) {
    return 'Última coleta $when';
  }

  @override
  String get statusNever => 'Nunca coletado';

  @override
  String statusSemantics(String status) {
    return 'Status: $status';
  }

  @override
  String get gathering => 'Coletando…';

  @override
  String get gatheringSemantics => 'Coletando, aguarde';

  @override
  String get gatheringProgress => 'Coletando';

  @override
  String get gatherNow => 'Coletar agora';

  @override
  String get countCharacters => 'Personagens';

  @override
  String get countJournalLines => 'Linhas do diário';

  @override
  String get countScreenshots => 'Capturas de tela';

  @override
  String countSemantics(String label, int value) {
    return '$label: $value';
  }

  @override
  String get charactersTitle => 'Personagens';

  @override
  String get noCharacters =>
      'Ainda não há personagens. Clique em Coletar agora.';

  @override
  String characterLevel(int level) {
    return 'Nível $level';
  }

  @override
  String get backupFolderTitle => 'Pasta de backup';

  @override
  String get notSet => 'Não definida';

  @override
  String backupSize(String size) {
    return 'Tamanho: $size';
  }

  @override
  String get openBackupFolder => 'Abrir pasta de backup';

  @override
  String get openLatestData => 'Abrir dados mais recentes';

  @override
  String get openFolderFailed =>
      'Não conseguimos abrir esta pasta. Se você ainda não coletou, clique primeiro em Coletar agora.';

  @override
  String get dismiss => 'Fechar';

  @override
  String get showWebsiteTab => 'Mostrar a aba Site';

  @override
  String andMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'e mais $count',
      one: 'e mais 1',
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
  String get classWarrior => 'Guerreiro';

  @override
  String get classPaladin => 'Paladino';

  @override
  String get classHunter => 'Caçador';

  @override
  String get classRogue => 'Ladino';

  @override
  String get classPriest => 'Sacerdote';

  @override
  String get classDeathKnight => 'Cavaleiro da Morte';

  @override
  String get classShaman => 'Xamã';

  @override
  String get classMage => 'Mago';

  @override
  String get classWarlock => 'Bruxo';

  @override
  String get classMonk => 'Monge';

  @override
  String get classDruid => 'Druida';

  @override
  String get classDemonHunter => 'Caçador de Demônios';

  @override
  String get classEvoker => 'Conjurante';

  @override
  String get settingsSaveFailed =>
      'Não conseguimos salvar as suas configurações. Confira se o seu disco tem espaço livre e mude a configuração de novo.';

  @override
  String get settingsDamaged =>
      'O seu arquivo de configurações estava danificado, então o app iniciou com as configurações padrão. Confira as suas pastas e os seus botões.';

  @override
  String get wowFolderTitle => 'Pasta do WoW';

  @override
  String get changeWowFolderSemantics => 'Mudar a pasta do WoW';

  @override
  String get changeBackupFolderSemantics => 'Mudar a pasta de backup';

  @override
  String get change => 'Mudar';

  @override
  String get watchTitle => 'Monitorar';

  @override
  String get watchSubtitle => 'Coletar sozinho sempre que o jogo salvar.';

  @override
  String get startAtLoginTitle => 'Iniciar ao entrar';

  @override
  String get startAtLoginSubtitle =>
      'Iniciar o app oculto quando você entrar no sistema.';

  @override
  String get languageTitle => 'Idioma';

  @override
  String get languageSystem => 'Sistema';

  @override
  String get versionTitle => 'Versão';

  @override
  String versionText(String version, String core) {
    return 'WoW Journey $version, $core';
  }

  @override
  String get wizardTitle => 'Boas-vindas ao WoW Journey';

  @override
  String wizardStep(int step, int total) {
    return 'Passo $step de $total';
  }

  @override
  String get back => 'Voltar';

  @override
  String backSemantics(int step) {
    return 'Voltar ao passo $step';
  }

  @override
  String get next => 'Avançar';

  @override
  String get nextSemantics => 'Próximo passo';

  @override
  String get finish => 'Concluir';

  @override
  String get finishSemantics => 'Concluir a configuração';

  @override
  String get wowStepTitle => 'Sua pasta do WoW';

  @override
  String get wowStepIntro =>
      'Lemos os arquivos que os addons do Memories salvam nesta pasta. Nunca os alteramos.';

  @override
  String get lookingForWow => 'Procurando o World of Warcraft…';

  @override
  String get noWowFound =>
      'Não conseguimos encontrar o World of Warcraft. Escolha a pasta de uma versão do jogo, como _retail_, dentro da sua pasta do World of Warcraft.';

  @override
  String get chooseFolder => 'Escolher pasta';

  @override
  String get chooseWowSemantics => 'Escolher a pasta do WoW';

  @override
  String get noMemoriesYet => 'Ainda não há dados do Memories.';

  @override
  String wowFolderSemantics(String path) {
    return 'Pasta do WoW: $path';
  }

  @override
  String get backupStepTitle => 'Sua pasta de backup';

  @override
  String get backupStepIntro =>
      'Guardamos aqui uma cópia dos seus arquivos do jogo e das suas capturas de tela.';

  @override
  String backupFolderSemantics(String path) {
    return 'Pasta de backup: $path';
  }

  @override
  String get backupFolderSemanticsNotSet => 'Pasta de backup: não definida';

  @override
  String get chooseBackupPrompt => 'Escolha uma pasta de backup.';

  @override
  String get switchStepTitle => 'Como o app funciona';

  @override
  String get switchStepIntro =>
      'Você pode mudar isso depois, em Configurações.';

  @override
  String get useThisFolder => 'Usar esta pasta';

  @override
  String get pickerFailed =>
      'Não conseguimos abrir o seletor de pastas. Tente de novo ou reinicie o app.';

  @override
  String get checkFailed =>
      'Não conseguimos verificar esta pasta. Tente de novo ou escolha outra pasta.';

  @override
  String get chooseGameVersion => 'Escolha uma versão do jogo';

  @override
  String get backupInsideWow =>
      'Esta pasta está dentro da sua pasta do World of Warcraft, ou a contém. Escolha uma pasta de backup fora da pasta do jogo.';

  @override
  String get backupInsideWowFirst =>
      'A sua pasta de backup está dentro desta pasta do World of Warcraft, ou a contém. Escolha primeiro outra pasta de backup e depois esta pasta do WoW.';

  @override
  String get useBackupTitle => 'Usar esta pasta de backup?';

  @override
  String useBackupBody(String path) {
    return 'As novas coletas vão para $path. A sua pasta de backup antiga continua como está. Não a movemos nem a apagamos.';
  }

  @override
  String get cancel => 'Cancelar';

  @override
  String get flavorReady => 'Esta pasta do WoW está pronta.';

  @override
  String get flavorReadyNoData =>
      'Esta pasta do WoW está pronta, mas ainda não tem dados do Memories. Jogue com os addons do Memories ativados. O jogo salva os arquivos dele quando você sai ou digita /reload.';

  @override
  String get flavorNoWtf =>
      'Esta pasta não é uma pasta do jogo WoW. Ela não tem a pasta WTF/Account. Escolha a pasta de uma versão do jogo dentro da sua pasta do World of Warcraft, como _retail_.';

  @override
  String flavorInstallFolder(int count, String names) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Esta é a pasta do World of Warcraft. Ela tem $count versões do jogo: $names. Escolha uma delas.',
      one:
          'Esta é a pasta do World of Warcraft. Ela tem uma versão do jogo: $names. Escolha essa pasta.',
    );
    return '$_temp0';
  }

  @override
  String get flavorNotADirectory =>
      'Isto não é uma pasta, ou ela não existe mais. Escolha uma pasta.';

  @override
  String get flavorNotReadable =>
      'Esta pasta, ou uma pasta dentro dela, não pode ser lida. Confira se o seu usuário pode abri-la e escolha-a de novo.';

  @override
  String get websiteTitle => 'Site';

  @override
  String websiteCardTitle(String site) {
    return 'Site: $site';
  }

  @override
  String get registrationTitle => 'Cadastro';

  @override
  String get unlistedText =>
      'As páginas dos seus personagens não são listadas: qualquer pessoa com o link pode abri-las.';

  @override
  String get lostKeyText =>
      'Se você reinstalar o app ou criar uma chave nova, copie a sua chave nova e peça ao administrador do site para mover os seus personagens para ela.';

  @override
  String get websiteAddressLabel => 'Endereço do site';

  @override
  String get checkSiteLabel => 'Verificar';

  @override
  String get inviteCodeLabel => 'Código de convite';

  @override
  String get registerLabel => 'Cadastrar';

  @override
  String get uploadSwitchTitle => 'Envio';

  @override
  String get uploadSwitchSubtitle =>
      'Enviar a sua jornada para o site depois de cada coleta.';

  @override
  String get uploadNowLabel => 'Enviar agora';

  @override
  String get uploadingLabel => 'Enviando…';

  @override
  String get uploadingSemantics => 'Enviando, aguarde';

  @override
  String get uploadPausedText =>
      'Envio pausado. Ele continua depois da próxima coleta.';

  @override
  String get requestScreenshotsLabel => 'Pedir capturas de tela';

  @override
  String get copyLinkLabel => 'Copiar link';

  @override
  String copyLinkSemantics(String name) {
    return 'Copiar o link de $name';
  }

  @override
  String get removeFromWebsiteLabel => 'Remover do site';

  @override
  String removeFromWebsiteSemantics(String name) {
    return 'Remover $name do site';
  }

  @override
  String get linkCopiedText => 'Link copiado';

  @override
  String get removeLabel => 'Remover';

  @override
  String siteFoundOpen(String name) {
    return '$name encontrado. Qualquer pessoa pode se cadastrar aqui.';
  }

  @override
  String siteFoundInvite(String name) {
    return '$name encontrado. Para se cadastrar, você precisa de um código de convite do administrador do site.';
  }

  @override
  String get notAMemoriesSite =>
      'Este endereço não parece um site do Memories. Confira o endereço.';

  @override
  String registeredText(String site) {
    return 'Cadastrado em $site.';
  }

  @override
  String notRegisteredText(String site) {
    return 'Não cadastrado em $site. Cadastre-se para enviar a sua jornada.';
  }

  @override
  String fingerprintText(String fingerprint) {
    return 'Sua chave: $fingerprint';
  }

  @override
  String get copyKeyLabel => 'Copiar a sua chave';

  @override
  String get copyKeySemantics =>
      'Copiar a sua chave para o administrador do site';

  @override
  String get keyCopiedText => 'Chave copiada';

  @override
  String get newKeyLabel => 'Criar uma chave nova';

  @override
  String get newKeyTitle => 'Criar uma chave nova?';

  @override
  String newKeyQuestionText(String site) {
    return 'Faça isso só quando o site tiver bloqueado ou recusado esta chave. O app cria uma chave nova e guarda uma cópia da antiga. Os seus personagens em $site ficam com a chave antiga. O administrador do site pode movê-los para a chave nova. Depois, cadastre-se de novo. O site pode pedir um código de convite novo. O app envia seus personagens selecionados de novo. O envio fica desativado até você ativá-lo.';
  }

  @override
  String get newKeyDoneText =>
      'Chave nova criada. Cadastre-se de novo para enviar.';

  @override
  String get errKeyNotReplaced =>
      'O app não conseguiu criar uma chave nova, então mantém a antiga. Confira se a pasta dele pode ser gravada e tem espaço livre, e tente de novo.';

  @override
  String get screenshotsNone =>
      'As capturas de tela não são enviadas. Peça ao administrador do site para aprová-las.';

  @override
  String get screenshotsPending =>
      'Aguardando o administrador do site aprovar as suas capturas de tela.';

  @override
  String get screenshotsApproved =>
      'As suas capturas de tela são enviadas com a sua jornada.';

  @override
  String get screenshotsDenied =>
      'O administrador do site não aprovou as capturas de tela. Você pode pedir de novo.';

  @override
  String cardNotRegistered(String site) {
    return 'Você não está cadastrado em $site. Cadastre-se abaixo para compartilhar a sua jornada.';
  }

  @override
  String get cardUploadOff =>
      'O envio está desativado. Ative o botão Envio abaixo para enviar a sua jornada.';

  @override
  String get selectionTitle => 'Personagens para enviar';

  @override
  String get selectionHint => 'Escolha os personagens que quer enviar.';

  @override
  String get selectionNote =>
      'Personagens novos não são enviados até você marcá-los. Desmarcar um personagem só impede os envios seguintes; nada é removido do site.';

  @override
  String get selectAllLabel => 'Selecionar tudo';

  @override
  String get selectNoneLabel => 'Selecionar nenhum';

  @override
  String uploadProgress(int done, int total) {
    return 'Enviando $done de $total';
  }

  @override
  String get lastUploadNever => 'Nada foi enviado ainda.';

  @override
  String lastUpload(String time) {
    return 'Último envio $time';
  }

  @override
  String syncUploaded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count personagens enviados',
      one: '1 personagem enviado',
    );
    return '$_temp0';
  }

  @override
  String syncShots(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count capturas de tela enviadas',
      one: '1 captura de tela enviada',
    );
    return '$_temp0';
  }

  @override
  String get syncUpToDate => 'tudo está em dia';

  @override
  String syncFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count personagens falharam',
      one: '1 personagem falhou',
    );
    return '$_temp0';
  }

  @override
  String syncShotsFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count capturas de tela falharam',
      one: '1 captura de tela falhou',
    );
    return '$_temp0';
  }

  @override
  String errNetwork(String host) {
    return 'Não foi possível alcançar $host. Confira a conexão com a internet e o endereço do site.';
  }

  @override
  String get errBadResponse =>
      'O site enviou uma resposta que este programa não entende. Confira o endereço do site.';

  @override
  String get errBadFiles =>
      'Um arquivo da sua jornada está ausente ou não pode ser lido, então não foi enviado. Colete de novo e tente de novo.';

  @override
  String get errNoIndex =>
      'Não foi possível ler o index.json dos dados mais recentes. Execute primeiro a coleta e tente de novo.';

  @override
  String get errBadKey =>
      'O arquivo de chave do app não pode ser lido nem gravado. Confira as permissões dele e o espaço livre da pasta dele.';

  @override
  String get errBadSite =>
      'O endereço do site não é válido. Escreva-o assim: https://example.com.';

  @override
  String get errBadState =>
      'O app não conseguiu salvar sua escolha de personagens para enviar. Verifique se é possível gravar na pasta do app e tente de novo.';

  @override
  String get errFailed =>
      'O envio parou por causa de um problema dentro do app. Tente de novo depois da próxima coleta.';

  @override
  String errHttp(String status) {
    return 'O site respondeu com o status $status. Tente de novo mais tarde e confira o endereço do site.';
  }

  @override
  String errKeyRevoked(String site) {
    return 'O administrador do site bloqueou a chave deste app. Os envios para $site estão desativados.';
  }

  @override
  String get errNotRegistered =>
      'O site ainda não conhece a chave deste app. Cadastre-se na aba Site.';

  @override
  String errClaimed(String name, String realm) {
    return 'Outro jogador já enviou $name em $realm. Pergunte ao administrador do site.';
  }

  @override
  String get realmUnknown => 'o reino dele';

  @override
  String get errInvalid =>
      'O site não aceitou os dados. Corrija os arquivos salvos e envie de novo.';

  @override
  String get errInviteInvalid =>
      'O código de convite não é válido. Peça um novo ao administrador do site.';

  @override
  String get errBadSignature =>
      'O site não aceitou a assinatura do app. Confira se o relógio do seu computador está certo e tente de novo.';

  @override
  String get errRateLimited =>
      'Muitas solicitações. Espere um minuto e tente de novo.';

  @override
  String get errBusy =>
      'O site está ocupado com outros envios. Tente de novo em alguns minutos.';

  @override
  String get errQuota =>
      'O site não tem mais espaço para os seus dados. Pergunte ao administrador do site.';

  @override
  String get errTooLarge =>
      'Os seus dados são grandes demais para este site. Peça ao administrador do site para aumentar o limite.';

  @override
  String get errInternal =>
      'O site teve um problema. Tente de novo em alguns minutos.';

  @override
  String get errBadRequest =>
      'O site não conseguiu ler a solicitação. Tente de novo e atualize o app se continuar acontecendo.';

  @override
  String get errNotFound =>
      'Este site não tem esse personagem para esta chave.';

  @override
  String get errScreenshotsNotApproved =>
      'O administrador do site ainda não aprovou as suas capturas de tela.';

  @override
  String get errUnsupportedImage =>
      'O site não aceitou uma captura de tela porque o tipo de imagem dela não é compatível.';

  @override
  String get errNotReferenced =>
      'Uma captura de tela não pertence a nenhuma linha do diário, então o site não a guardou.';

  @override
  String get errGuidMismatch =>
      'Este nome de personagem já pertence a outro personagem no site. Pergunte ao administrador do site.';

  @override
  String get errGzipRequired =>
      'O envio não estava compactado como o site precisa. Atualize o app e tente de novo.';

  @override
  String namedError(String name, String text) {
    return '$name: $text';
  }

  @override
  String rejectedText(String name, String problems, int more) {
    String _temp0 = intl.Intl.pluralLogic(
      more,
      locale: localeName,
      other: ' E mais $more problemas.',
      one: ' E mais 1 problema.',
      zero: '',
    );
    return 'O site não aceitou os dados de $name: $problems$_temp0 Corrija os arquivos salvos e envie de novo.';
  }

  @override
  String get siteInvalid =>
      'O endereço do site não é válido. Escreva-o assim: https://example.com.';

  @override
  String get siteNeedsHost =>
      'O endereço do site precisa de um esquema e de um host, como https://example.com.';

  @override
  String get siteNeedsHttps => 'O endereço do site deve começar com https://.';

  @override
  String get siteHttpLoopback =>
      'O endereço do site deve começar com https://. O http:// simples só é permitido para localhost, 127.0.0.1 e [::1].';

  @override
  String get siteUserInfo =>
      'O endereço do site não pode ter nome de usuário nem senha.';

  @override
  String get siteQuery =>
      'O endereço do site não pode ter consulta nem fragmento.';

  @override
  String get sitePath =>
      'O endereço do site não pode ter um caminho. Use o endereço do próprio site, como https://example.com.';

  @override
  String removeQuestionText(String name, String site) {
    return 'Remover $name de $site? A página e os dados dela são apagados.';
  }

  @override
  String removedText(String name) {
    return '$name foi removido do site e desmarcado. Marque-o de novo para enviá-lo.';
  }

  @override
  String get busyText =>
      'O app está ocupado com o site. Tente de novo quando o envio terminar.';

  @override
  String get genericFailureText =>
      'Algo deu errado com o site. Tente de novo em alguns minutos.';

  @override
  String get notAnswering =>
      'O WoW Journey já está em execução, mas não respondeu. Use Sair no menu do ícone dele na bandeja, ou encerre-o no gerenciador de tarefas, e inicie-o de novo.';

  @override
  String get close => 'Fechar';

  @override
  String get trayGatherNow => 'Coletar agora';

  @override
  String get trayOpenWindow => 'Abrir janela';

  @override
  String get trayOpenBackupFolder => 'Abrir pasta de backup';

  @override
  String get trayQuit => 'Sair';
}
