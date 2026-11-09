/// The main screen: a header and three tabs. Overview has the status, Gather now,
/// the counts, the characters, the problems and the backup folder. Website has the
/// upload status and the registration. Settings has the folders and the switches.
library;

import 'package:flutter/material.dart';
import 'package:memories_core/memories_core.dart';
import 'package:path/path.dart' as p;

import '../../l10n/app_localizations.dart';
import '../gather/gather_controller.dart';
import '../platform/services.dart';
import '../settings/settings_controller.dart';
import '../theme/ak_widgets.dart';
import '../theme/tokens.dart';
import '../upload/upload_controller.dart';
import '../watch/watch_controller.dart';
import 'folder_flow.dart';
import 'messages.dart';
import 'settings_view.dart';
import 'website_card.dart';
import 'website_section.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.services,
    required this.settings,
    required this.gather,
    required this.watch,
    required this.upload,
    this.clock = DateTime.now,
  });

  final AppServices services;
  final SettingsController settings;
  final GatherController gather;
  final WatchController watch;
  final UploadController upload;
  final DateTime Function() clock;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _checkedFlavor;
  String? _checkedRoot;
  bool _wowGone = false;
  bool _started = false;
  int _tab = 0;

  SettingsController get _settings => widget.settings;
  GatherController get _gather => widget.gather;

  @override
  void initState() {
    super.initState();
    _settings.addListener(_onSettings);
    _onSettings();
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettings);
    super.dispose();
  }

  void _onSettings() {
    final s = _settings.settings;
    final flavorChanged = s.flavorDir != _checkedFlavor;
    final rootChanged = s.backupRoot != _checkedRoot;
    if (_started && (flavorChanged || rootChanged)) _gather.forget();
    _started = true;
    if (flavorChanged) {
      _checkedFlavor = s.flavorDir;
      _checkWowFolder(s.flavorDir);
    }
    if (rootChanged) {
      _checkedRoot = s.backupRoot;
      if (s.backupRoot != null) _gather.refresh(s.backupRoot!);
    }
  }

  Future<void> _checkWowFolder(String? dir) async {
    var gone = dir == null;
    if (dir != null) {
      try {
        gone = await widget.services.discovery.validate(dir) is! Valid;
      } on Object {
        gone = false;
      }
    }
    if (!mounted || dir != _settings.settings.flavorDir) return;
    setState(() => _wowGone = gone);
  }

  Future<void> _gatherNow() async {
    final s = _settings.settings;
    if (s.flavorDir == null || s.backupRoot == null) return;
    await _gather.gatherNow(flavorDir: s.flavorDir!, backupRoot: s.backupRoot!);
  }

  Future<void> _open(String? path) async {
    final ok = path != null && await widget.services.opener.open(path);
    if (ok || !mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(AppLocalizations.of(context).openFolderFailed)),
      );
  }

  String? get _latest {
    final root = _settings.settings.backupRoot;
    return root == null ? null : p.join(root, 'latest');
  }

  Future<void> _chooseWowFolder() async {
    final before = _settings.settings.flavorDir;
    await changeWowFolder(
      context,
      settings: _settings,
      picker: widget.services.picker,
      discovery: widget.services.discovery,
    );
    // The same folder chosen again, such as after its drive is back, leaves
    // the settings as they are, so no settings listener checks it. A new
    // folder is checked by [_onSettings].
    if (_settings.settings.flavorDir == before) await _checkWowFolder(before);
  }

  Future<void> _fix(IssueFix fix) => switch (fix) {
    IssueFix.chooseWowFolder => _chooseWowFolder(),
    IssueFix.chooseBackupFolder => changeBackupFolder(
      context,
      settings: _settings,
      picker: widget.services.picker,
    ),
    IssueFix.openLatest => _open(_latest),
    IssueFix.tryAgain => _gatherNow(),
  };

  List<AkTab> _tabs(AppLocalizations l) => [
    AkTab(id: 'Overview', label: l.tabOverview, icon: Icons.dashboard_outlined),
    AkTab(id: 'Website', label: l.tabWebsite, icon: Icons.cloud_outlined),
    AkTab(id: 'Settings', label: l.tabSettings, icon: Icons.settings_outlined),
  ];

  /// A tab page: the content in a scrolling column of at most 720 pixels.
  Widget _page(List<Widget> children) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: FocusTraversalGroup(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 16),
          // The settings message is the first line of each tab, so it scrolls with the tab.
          children: [
            if (_settings.notice != null) ...[
              _notice(context),
              const SizedBox(height: 12),
            ],
            ...children,
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ListenableBuilder(
            listenable: Listenable.merge([_settings, _gather, widget.watch]),
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AkHeader(title: l.appTitle),
                AkTabBar(
                  tabs: _tabs(l),
                  selected: _tab,
                  onSelected: (i) => setState(() => _tab = i),
                ),
                Expanded(
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      _page([
                        if (_wowGone) ...[
                          _wowGoneCard(context),
                          const SizedBox(height: 12),
                        ],
                        _statusCard(context),
                        const SizedBox(height: 12),
                        _uploadProblems(context),
                        const _HintCard(),
                        ..._issueCards(context),
                        const SizedBox(height: 12),
                        _counts(context),
                        const SizedBox(height: 12),
                        _characters(context),
                        const SizedBox(height: 12),
                        _backupCard(context),
                      ]),
                      _page([
                        WebsiteCard(
                          upload: widget.upload,
                          settings: _settings,
                          clock: widget.clock,
                        ),
                        const SizedBox(height: 12),
                        Card(
                          child: WebsiteSection(
                            upload: widget.upload,
                            settings: _settings,
                          ),
                        ),
                      ]),
                      _page([
                        SettingsView(
                          services: widget.services,
                          settings: _settings,
                        ),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The problems of the last upload, on the first tab so that they are not missed. The details are on the Website tab.
  Widget _uploadProblems(BuildContext context) => ListenableBuilder(
    listenable: widget.upload,
    builder: (context, _) {
      final issues = widget.upload.issues;
      if (issues.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Card(
          color: Theme.of(context).colorScheme.errorContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final issue in issues)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      noticeText(AppLocalizations.of(context), issue),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: () => setState(() => _tab = 1),
                  child: Text(AppLocalizations.of(context).showWebsiteTab),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

  Widget _notice(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: ListTile(
      leading: const Icon(Icons.info_outline),
      title: Text(
        settingsNoticeText(AppLocalizations.of(context), _settings.notice!),
      ),
      trailing: IconButton(
        tooltip: AppLocalizations.of(context).dismiss,
        icon: const Icon(Icons.close),
        onPressed: _settings.dismissNotice,
      ),
    ),
  );

  Widget _wowGoneCard(BuildContext context) => _ProblemCard(
    text: AppLocalizations.of(context).wowFolderGoneText,
    paths: [?_settings.settings.flavorDir],
    fix: IssueFix.chooseWowFolder,
    onFix: _fix,
  );

  String _statusText(AppLocalizations l) {
    final last = _gather.lastGathered;
    final when = last == null ? null : formatTime(l, last, widget.clock());
    return switch (_gather.state) {
      GatherState.running => l.statusGathering,
      GatherState.failed => l.statusFailed,
      GatherState.done when _gather.issues.isNotEmpty => l.statusDoneProblems(
        when!,
      ),
      GatherState.done => l.statusDone(when!),
      GatherState.idle when when != null => l.statusIdleLast(when),
      GatherState.idle => l.statusNever,
    };
  }

  Widget _statusCard(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final s = _settings.settings;
    final canGather =
        !_gather.running && s.flavorDir != null && s.backupRoot != null;
    final status = _statusText(l);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              liveRegion: true,
              label: l.statusSemantics(status),
              excludeSemantics: true,
              container: true,
              child: Text(status, style: theme.textTheme.titleMedium),
            ),
            if (widget.watch.watching) ...[
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: AkTag(l.watchingText),
              ),
            ],
            const SizedBox(height: 12),
            if (_gather.running) ...[
              LinearProgressIndicator(semanticsLabel: l.gatheringProgress),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: canGather ? _gatherNow : null,
              icon: const Icon(Icons.sync),
              label: _gather.running
                  ? Text(l.gathering, semanticsLabel: l.gatheringSemantics)
                  : Text(l.gatherNow),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _issueCards(BuildContext context) {
    final l = AppLocalizations.of(context);
    final byCode = <GatherIssueCode, List<GatherIssue>>{};
    for (final i in _gather.issues) {
      byCode.putIfAbsent(i.code, () => []).add(i);
    }
    return [
      for (final MapEntry(key: code, value: issues) in byCode.entries)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _ProblemCard(
            text: issueText(l, code),
            paths: [for (final i in issues) ?i.path],
            fix: issueFix(code),
            onFix: _fix,
          ),
        ),
    ];
  }

  // The counts come from index.json, like the list below them: it also keeps
  // the characters that this gather did not write.
  Widget _counts(BuildContext context) {
    final l = AppLocalizations.of(context);
    final snap = _gather.snapshot;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _Count(label: l.countCharacters, value: snap.characters.length),
        _Count(label: l.countJournalLines, value: snap.lines),
        _Count(label: l.countScreenshots, value: snap.screenshots),
      ],
    );
  }

  Widget _characters(BuildContext context) {
    final l = AppLocalizations.of(context);
    final list = _gather.snapshot.characters;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: AkPanelTitle(l.charactersTitle),
          ),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(l.noCharacters),
            ),
          for (final c in list)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(c.name),
              subtitle: _characterDetail(c, l),
            ),
        ],
      ),
    );
  }

  /// The realm, the level and the class of a character. The class has its game colour.
  Widget _characterDetail(CharacterSummary c, AppLocalizations l) {
    final cls = c.className;
    final parts = [
      c.realm,
      if (c.level != null) l.characterLevel(c.level!),
    ].where((e) => e.isNotEmpty).toList();
    final hasClass = cls != null && cls.isNotEmpty;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: parts.join(' · ')),
          if (hasClass) ...[
            if (parts.isNotEmpty) const TextSpan(text: ' · '),
            TextSpan(
              text: className(l, cls),
              style: TextStyle(
                color: classColours[cls.toUpperCase()] ?? Tokens.text,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _backupCard(BuildContext context) {
    final l = AppLocalizations.of(context);
    final root = _settings.settings.backupRoot;
    final size = formatSize(l, _gather.snapshot.sizeBytes);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AkPanelTitle(l.backupFolderTitle),
            Text(root ?? l.notSet),
            const SizedBox(height: 4),
            Text(l.backupSize(size)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _open(root),
                  icon: const Icon(Icons.folder_open_outlined),
                  label: Text(l.openBackupFolder),
                ),
                OutlinedButton.icon(
                  onPressed: () => _open(_latest),
                  icon: const Icon(Icons.folder_special_outlined),
                  label: Text(l.openLatestData),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HintCard extends StatelessWidget {
  const _HintCard();

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerHighest,
    child: ListTile(
      leading: const Icon(Icons.lightbulb_outline),
      title: Text(AppLocalizations.of(context).saveHintText),
    ),
  );
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: AppLocalizations.of(context).countSemantics(label, value),
      excludeSemantics: true,
      container: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 120),
        child: Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$value', style: theme.textTheme.headlineSmall),
                Text(label),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One problem: its text, the files it names, and its fix button.
class _ProblemCard extends StatelessWidget {
  const _ProblemCard({
    required this.text,
    required this.paths,
    required this.fix,
    required this.onFix,
  });

  static const int _shownPaths = 3;

  final String text;
  final List<String> paths;
  final IssueFix? fix;
  final Future<void> Function(IssueFix fix) onFix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    final unique = paths.toSet().toList();
    final more = unique.length - _shownPaths;
    return Card(
      color: theme.colorScheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_outlined,
                  color: theme.colorScheme.onErrorContainer,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    text,
                    style: TextStyle(color: theme.colorScheme.onErrorContainer),
                  ),
                ),
              ],
            ),
            for (final path in unique.take(_shownPaths))
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 36),
                child: Text(path, style: theme.textTheme.bodySmall),
              ),
            if (more > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 36),
                child: Text(l.andMore(more), style: theme.textTheme.bodySmall),
              ),
            if (fix != null) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(left: 36),
                child: FilledButton.tonal(
                  onPressed: () => onFix(fix!),
                  child: Text(fix!.label(l)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
