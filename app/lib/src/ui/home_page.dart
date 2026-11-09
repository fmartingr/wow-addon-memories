/// The main screen: a header and three tabs. Overview has the status, Gather now,
/// the counts, the characters, the problems and the backup folder. Website has the
/// upload status and the registration. Settings has the folders and the switches.
library;

import 'package:flutter/material.dart';
import 'package:memories_core/memories_core.dart';
import 'package:path/path.dart' as p;

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
        const SnackBar(
          content: Text(
            'We could not open this folder. If you have not gathered yet, '
            'click Gather now first.',
          ),
        ),
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

  static const _tabs = [
    AkTab(label: 'Overview', icon: Icons.dashboard_outlined),
    AkTab(label: 'Website', icon: Icons.cloud_outlined),
    AkTab(label: 'Settings', icon: Icons.settings_outlined),
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
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ListenableBuilder(
            listenable: Listenable.merge([_settings, _gather, widget.watch]),
            builder: (context, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const AkHeader(title: 'WoW Journey'),
                AkTabBar(
                  tabs: _tabs,
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
                      issue,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                TextButton(
                  onPressed: () => setState(() => _tab = 1),
                  child: const Text(showWebsiteLabel),
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
      title: Text(_settings.notice!),
      trailing: IconButton(
        tooltip: 'Dismiss',
        icon: const Icon(Icons.close),
        onPressed: _settings.dismissNotice,
      ),
    ),
  );

  Widget _wowGoneCard(BuildContext context) => _ProblemCard(
    text: wowFolderGoneText,
    paths: [?_settings.settings.flavorDir],
    fix: IssueFix.chooseWowFolder,
    onFix: _fix,
  );

  String _statusText() {
    final last = _gather.lastGathered;
    final when = last == null ? null : formatTime(last, widget.clock());
    return switch (_gather.state) {
      GatherState.running => 'Gathering your journey…',
      GatherState.failed =>
        'The last gather did not finish. See the problem below.',
      GatherState.done when _gather.issues.isNotEmpty =>
        'Gathered with problems. Last gathered $when',
      GatherState.done => 'Up to date. Last gathered $when',
      GatherState.idle when when != null => 'Last gathered $when',
      GatherState.idle => 'Never gathered',
    };
  }

  Widget _statusCard(BuildContext context) {
    final theme = Theme.of(context);
    final s = _settings.settings;
    final canGather =
        !_gather.running && s.flavorDir != null && s.backupRoot != null;
    final status = _statusText();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              liveRegion: true,
              label: 'Status: $status',
              excludeSemantics: true,
              container: true,
              child: Text(status, style: theme.textTheme.titleMedium),
            ),
            if (widget.watch.watching) ...[
              const SizedBox(height: 4),
              const Align(
                alignment: Alignment.centerLeft,
                child: AkTag(watchingText),
              ),
            ],
            const SizedBox(height: 12),
            if (_gather.running) ...[
              const LinearProgressIndicator(semanticsLabel: 'Gathering'),
              const SizedBox(height: 12),
            ],
            FilledButton.icon(
              onPressed: canGather ? _gatherNow : null,
              icon: const Icon(Icons.sync),
              label: _gather.running
                  ? const Text(
                      'Gathering…',
                      semanticsLabel: 'Gathering, please wait',
                    )
                  : const Text('Gather now'),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _issueCards(BuildContext context) {
    final byCode = <GatherIssueCode, List<GatherIssue>>{};
    for (final i in _gather.issues) {
      byCode.putIfAbsent(i.code, () => []).add(i);
    }
    return [
      for (final MapEntry(key: code, value: issues) in byCode.entries)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: _ProblemCard(
            text: issueText(code),
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
    final snap = _gather.snapshot;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _Count(label: 'Characters', value: snap.characters.length),
        _Count(label: 'Journal lines', value: snap.lines),
        _Count(label: 'Screenshots', value: snap.screenshots),
      ],
    );
  }

  Widget _characters(BuildContext context) {
    final list = _gather.snapshot.characters;
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: const AkPanelTitle('Characters'),
          ),
          if (list.isEmpty)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text('No characters yet. Click Gather now.'),
            ),
          for (final c in list)
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(c.name),
              subtitle: _characterDetail(c),
            ),
        ],
      ),
    );
  }

  /// The realm, the level and the class of a character. The class has its game colour.
  Widget _characterDetail(CharacterSummary c) {
    final cls = c.className;
    final parts = [
      c.realm,
      if (c.level != null) 'Level ${c.level}',
    ].where((e) => e.isNotEmpty).toList();
    final hasClass = cls != null && cls.isNotEmpty;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: parts.join(' · ')),
          if (hasClass) ...[
            if (parts.isNotEmpty) const TextSpan(text: ' · '),
            TextSpan(
              text: className(cls),
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
    final root = _settings.settings.backupRoot;
    final size = formatSize(_gather.snapshot.sizeBytes);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AkPanelTitle('Backup folder'),
            Text(root ?? 'Not set'),
            const SizedBox(height: 4),
            Text('Size: $size'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _open(root),
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('Open backup folder'),
                ),
                OutlinedButton.icon(
                  onPressed: () => _open(_latest),
                  icon: const Icon(Icons.folder_special_outlined),
                  label: const Text('Open latest data'),
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
    child: const ListTile(
      leading: Icon(Icons.lightbulb_outline),
      title: Text(saveHintText),
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
      label: '$label: $value',
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
                child: Text(
                  more == 1 ? 'and 1 more' : 'and $more more',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            if (fix != null) ...[
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.only(left: 36),
                child: FilledButton.tonal(
                  onPressed: () => onFix(fix!),
                  child: Text(fix!.label),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
