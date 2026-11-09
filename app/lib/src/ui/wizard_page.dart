/// The first-run wizard: the WoW folder, the backup folder and the switches.
library;

import 'package:flutter/material.dart';
import 'package:memories_core/memories_core.dart';
import 'package:path/path.dart' as p;

import '../../l10n/app_localizations.dart';
import '../platform/documents_dir.dart';
import '../platform/services.dart';
import '../settings/settings.dart';
import '../settings/settings_store.dart';
import 'folder_flow.dart';
import 'messages.dart';
import 'switch_tiles.dart';

/// Three steps with Back and Next. Finish gives the chosen settings to
/// [onFinish], with `wizardDone` set.
class WizardPage extends StatefulWidget {
  const WizardPage({
    super.key,
    required this.services,
    required this.initial,
    required this.onFinish,
    this.notice,
  });

  final AppServices services;
  final Settings initial;
  final Future<void> Function(Settings settings) onFinish;

  /// A message about the settings file, shown above the steps.
  final SettingsNotice? notice;

  @override
  State<WizardPage> createState() => _WizardPageState();
}

/// Why the backup folder step shows a problem.
enum _BackupProblem { insideGame, pickerFailed }

class _WizardPageState extends State<WizardPage> {
  int _step = 0;

  bool _searching = true;
  bool _picking = false;
  List<WowFolder> _folders = const [];
  WowFolder? _selected;
  WowPick? _wowPick;

  String? _backupRoot;
  _BackupProblem? _backupProblem;

  late bool _watch = widget.initial.watch;
  late bool _startAtLogin = widget.initial.startAtLogin;
  bool _finishing = false;

  @override
  void initState() {
    super.initState();
    _backupRoot = widget.initial.backupRoot;
    _discover();
    if (_backupRoot == null) _loadDefaultRoot();
  }

  Future<void> _discover() async {
    List<WowFolder> found;
    try {
      found = await widget.services.discovery.discover();
    } on Object {
      found = const [];
    }
    if (!mounted) return;
    setState(() {
      _searching = false;
      _folders = found;
      _selected = found.isEmpty ? null : found.first;
    });
    if (found.isEmpty) await _choose();
  }

  Future<void> _loadDefaultRoot() async {
    String? root;
    try {
      root = await defaultBackupRoot(widget.services.directories);
    } on Object {
      root = null;
    }
    if (!mounted || _backupRoot != null) return;
    setState(() => _backupRoot = root);
  }

  Future<void> _choose() async {
    if (_picking) return;
    setState(() => _picking = true);
    final pick = await pickWowFolder(
      widget.services.picker,
      widget.services.discovery,
      confirmText: AppLocalizations.of(context).useThisFolder,
      initialDirectory: _selected?.installDir,
    );
    if (!mounted) return;
    setState(() {
      _picking = false;
      switch (pick) {
        case WowPickCancelled():
          break;
        case WowPickRefused():
          _wowPick = pick;
        case WowPicked(:final folder):
          _folders = [folder];
          _selected = folder;
          _wowPick = null;
        case WowPickChoices(:final folders):
          _folders = folders;
          _selected = folders.first;
          _wowPick = pick;
      }
    });
  }

  Future<void> _changeBackup() async {
    if (_picking) return;
    setState(() => _picking = true);
    final confirmText = AppLocalizations.of(context).useThisFolder;
    String? path;
    var failed = false;
    try {
      path = await widget.services.picker.pickFolder(
        initialDirectory: _backupRoot == null ? null : p.dirname(_backupRoot!),
        confirmText: confirmText,
      );
    } on Object {
      failed = true;
    }
    if (!mounted) return;
    setState(() {
      _picking = false;
      if (path == null && !failed) return;
      if (path == null) {
        _backupProblem = _BackupProblem.pickerFailed;
        return;
      }
      final overlaps = backupFolderOverlaps(path, _selected?.flavorDir);
      _backupProblem = overlaps ? _BackupProblem.insideGame : null;
      if (!overlaps) _backupRoot = path;
    });
  }

  bool get _canNext => switch (_step) {
    0 => _selected != null,
    1 =>
      _backupRoot != null &&
          !backupFolderOverlaps(_backupRoot!, _selected?.flavorDir),
    _ => !_finishing,
  };

  Future<void> _next() async {
    if (_step < 2) {
      setState(() {
        _step++;
        if (_step == 1 && _backupRoot != null) {
          _backupProblem =
              backupFolderOverlaps(_backupRoot!, _selected?.flavorDir)
              ? _BackupProblem.insideGame
              : null;
        }
      });
      return;
    }
    setState(() => _finishing = true);
    await widget.onFinish(
      widget.initial.copyWith(
        flavorDir: _selected!.flavorDir,
        backupRoot: _backupRoot,
        watch: _watch,
        startAtLogin: _startAtLogin,
        wizardDone: true,
      ),
    );
    if (mounted) setState(() => _finishing = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l.wizardTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: FocusTraversalGroup(
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        if (widget.notice != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              settingsNoticeText(l, widget.notice!),
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ),
                        Semantics(
                          header: true,
                          child: Text(
                            l.wizardStep(_step + 1, 3),
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...switch (_step) {
                          0 => _wowStep(theme, l),
                          1 => _backupStep(theme, l),
                          _ => _switchStep(theme, l),
                        },
                      ],
                    ),
                  ),
                  _buttons(l),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buttons(AppLocalizations l) => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        if (_step > 0)
          OutlinedButton(
            onPressed: _finishing ? null : () => setState(() => _step--),
            child: Text(l.back, semanticsLabel: l.backSemantics(_step)),
          ),
        const Spacer(),
        FilledButton(
          onPressed: _canNext ? _next : null,
          child: Text(
            _step == 2 ? l.finish : l.next,
            semanticsLabel: _step == 2 ? l.finishSemantics : l.nextSemantics,
          ),
        ),
      ],
    ),
  );

  List<Widget> _wowStep(ThemeData theme, AppLocalizations l) => [
    Semantics(
      header: true,
      child: Text(l.wowStepTitle, style: theme.textTheme.headlineSmall),
    ),
    const SizedBox(height: 8),
    Text(l.wowStepIntro),
    const SizedBox(height: 16),
    if (_searching)
      Row(
        children: [
          SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(semanticsLabel: l.lookingForWow),
          ),
          const SizedBox(width: 16),
          Expanded(child: Text(l.lookingForWow)),
        ],
      )
    else if (_folders.isEmpty)
      Text(l.noWowFound)
    else if (_folders.length == 1)
      _folderTile(_folders.single, theme, l)
    else
      RadioGroup<WowFolder>(
        groupValue: _selected,
        onChanged: (f) => setState(() => _selected = f),
        child: Column(
          children: [
            for (final f in _folders)
              RadioListTile<WowFolder>(
                value: f,
                title: Text(f.flavor),
                subtitle: Text(_folderDetail(f, l)),
              ),
          ],
        ),
      ),
    if (_wowPick != null)
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          pickText(l, _wowPick!)!,
          style: TextStyle(color: theme.colorScheme.error),
        ),
      ),
    const SizedBox(height: 16),
    if (!_searching)
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: OutlinedButton(
          onPressed: _picking ? null : _choose,
          child: _folders.isEmpty
              ? Text(l.chooseFolder, semanticsLabel: l.chooseWowSemantics)
              : Text(l.change, semanticsLabel: l.changeWowFolderSemantics),
        ),
      ),
  ];

  String _folderDetail(WowFolder f, AppLocalizations l) =>
      f.hasMemoriesData ? f.flavorDir : '${f.flavorDir}\n${l.noMemoriesYet}';

  Widget _folderTile(WowFolder f, ThemeData theme, AppLocalizations l) =>
      Semantics(
        label: l.wowFolderSemantics(f.flavorDir),
        excludeSemantics: true,
        container: true,
        child: Card(
          child: ListTile(
            leading: const Icon(Icons.folder_outlined),
            title: Text(f.flavor),
            subtitle: Text(_folderDetail(f, l)),
          ),
        ),
      );

  List<Widget> _backupStep(ThemeData theme, AppLocalizations l) => [
    Semantics(
      header: true,
      child: Text(l.backupStepTitle, style: theme.textTheme.headlineSmall),
    ),
    const SizedBox(height: 8),
    Text(l.backupStepIntro),
    const SizedBox(height: 16),
    Semantics(
      label: _backupRoot == null
          ? l.backupFolderSemanticsNotSet
          : l.backupFolderSemantics(_backupRoot!),
      excludeSemantics: true,
      container: true,
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.inventory_2_outlined),
          title: Text(_backupRoot ?? l.chooseBackupPrompt),
        ),
      ),
    ),
    if (_backupProblem != null)
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(switch (_backupProblem!) {
          _BackupProblem.insideGame => l.backupInsideWow,
          _BackupProblem.pickerFailed => l.pickerFailed,
        }, style: TextStyle(color: theme.colorScheme.error)),
      ),
    const SizedBox(height: 16),
    Align(
      alignment: AlignmentDirectional.centerStart,
      child: OutlinedButton(
        onPressed: _picking ? null : _changeBackup,
        child: Text(l.change, semanticsLabel: l.changeBackupFolderSemantics),
      ),
    ),
  ];

  List<Widget> _switchStep(ThemeData theme, AppLocalizations l) => [
    Semantics(
      header: true,
      child: Text(l.switchStepTitle, style: theme.textTheme.headlineSmall),
    ),
    const SizedBox(height: 8),
    Text(l.switchStepIntro),
    const SizedBox(height: 16),
    WatchTile(value: _watch, onChanged: (v) => setState(() => _watch = v)),
    StartAtLoginTile(
      value: _startAtLogin,
      onChanged: (v) => setState(() => _startAtLogin = v),
    ),
  ];
}
