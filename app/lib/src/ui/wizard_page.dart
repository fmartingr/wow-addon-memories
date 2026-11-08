/// The first-run wizard: the WoW folder, the backup folder and the switches.
library;

import 'package:flutter/material.dart';
import 'package:memories_core/memories_core.dart';
import 'package:path/path.dart' as p;

import '../platform/documents_dir.dart';
import '../platform/services.dart';
import '../settings/settings.dart';
import 'folder_flow.dart';
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
  final String? notice;

  @override
  State<WizardPage> createState() => _WizardPageState();
}

class _WizardPageState extends State<WizardPage> {
  int _step = 0;

  bool _searching = true;
  bool _picking = false;
  List<WowFolder> _folders = const [];
  WowFolder? _selected;
  String? _wowMessage;

  String? _backupRoot;
  String? _backupMessage;

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
      initialDirectory: _selected?.installDir,
    );
    if (!mounted) return;
    setState(() {
      _picking = false;
      switch (pick) {
        case WowPickCancelled():
          break;
        case WowPickRefused(:final message):
          _wowMessage = message;
        case WowPicked(:final folder):
          _folders = [folder];
          _selected = folder;
          _wowMessage = null;
        case WowPickChoices(:final folders, :final message):
          _folders = folders;
          _selected = folders.first;
          _wowMessage = message;
      }
    });
  }

  Future<void> _changeBackup() async {
    if (_picking) return;
    setState(() => _picking = true);
    String? path;
    String? failed;
    try {
      path = await widget.services.picker.pickFolder(
        initialDirectory: _backupRoot == null ? null : p.dirname(_backupRoot!),
        confirmText: 'Use this folder',
      );
    } on Object {
      failed = pickerFailedText;
    }
    if (!mounted) return;
    setState(() {
      _picking = false;
      if (path == null && failed == null) return;
      if (path == null) {
        _backupMessage = failed;
        return;
      }
      _backupMessage = backupFolderProblem(path, _selected?.flavorDir);
      if (_backupMessage == null) _backupRoot = path;
    });
  }

  bool get _canNext => switch (_step) {
    0 => _selected != null,
    1 =>
      _backupRoot != null &&
          backupFolderProblem(_backupRoot!, _selected?.flavorDir) == null,
    _ => !_finishing,
  };

  Future<void> _next() async {
    if (_step < 2) {
      setState(() {
        _step++;
        if (_step == 1 && _backupRoot != null) {
          _backupMessage = backupFolderProblem(
            _backupRoot!,
            _selected?.flavorDir,
          );
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
    return Scaffold(
      appBar: AppBar(title: const Text('Welcome to WoW Journey')),
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
                              widget.notice!,
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          ),
                        Semantics(
                          header: true,
                          child: Text(
                            'Step ${_step + 1} of 3',
                            style: theme.textTheme.labelLarge,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...switch (_step) {
                          0 => _wowStep(theme),
                          1 => _backupStep(theme),
                          _ => _switchStep(theme),
                        },
                      ],
                    ),
                  ),
                  _buttons(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buttons() => Padding(
    padding: const EdgeInsets.all(16),
    child: Row(
      children: [
        if (_step > 0)
          OutlinedButton(
            onPressed: _finishing ? null : () => setState(() => _step--),
            child: Text('Back', semanticsLabel: 'Back to step $_step'),
          ),
        const Spacer(),
        FilledButton(
          onPressed: _canNext ? _next : null,
          child: Text(
            _step == 2 ? 'Finish' : 'Next',
            semanticsLabel: _step == 2 ? 'Finish the setup' : 'Next step',
          ),
        ),
      ],
    ),
  );

  List<Widget> _wowStep(ThemeData theme) => [
    Semantics(
      header: true,
      child: Text('Your WoW folder', style: theme.textTheme.headlineSmall),
    ),
    const SizedBox(height: 8),
    const Text(
      'We read the files that the Memories addons save in this folder. '
      'We never change them.',
    ),
    const SizedBox(height: 16),
    if (_searching)
      const Row(
        children: [
          SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(
              semanticsLabel: 'Looking for World of Warcraft',
            ),
          ),
          SizedBox(width: 16),
          Expanded(child: Text('Looking for World of Warcraft…')),
        ],
      )
    else if (_folders.isEmpty)
      const Text(
        'We could not find World of Warcraft. Choose the folder of one game '
        'version, such as _retail_, inside your World of Warcraft folder.',
      )
    else if (_folders.length == 1)
      _folderTile(_folders.single, theme)
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
                subtitle: Text(_folderDetail(f)),
              ),
          ],
        ),
      ),
    if (_wowMessage != null)
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          _wowMessage!,
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
              ? const Text(
                  'Choose folder',
                  semanticsLabel: 'Choose the WoW folder',
                )
              : const Text('Change', semanticsLabel: 'Change the WoW folder'),
        ),
      ),
  ];

  String _folderDetail(WowFolder f) =>
      f.hasMemoriesData ? f.flavorDir : '${f.flavorDir}\nNo Memories data yet.';

  Widget _folderTile(WowFolder f, ThemeData theme) => Semantics(
    label: 'WoW folder: ${f.flavorDir}',
    excludeSemantics: true,
    container: true,
    child: Card(
      child: ListTile(
        leading: const Icon(Icons.folder_outlined),
        title: Text(f.flavor),
        subtitle: Text(_folderDetail(f)),
      ),
    ),
  );

  List<Widget> _backupStep(ThemeData theme) => [
    Semantics(
      header: true,
      child: Text('Your backup folder', style: theme.textTheme.headlineSmall),
    ),
    const SizedBox(height: 8),
    const Text('We keep a copy of your game files and your screenshots here.'),
    const SizedBox(height: 16),
    Semantics(
      label: 'Backup folder: ${_backupRoot ?? 'not set'}',
      excludeSemantics: true,
      container: true,
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.inventory_2_outlined),
          title: Text(_backupRoot ?? 'Choose a backup folder.'),
        ),
      ),
    ),
    if (_backupMessage != null)
      Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(
          _backupMessage!,
          style: TextStyle(color: theme.colorScheme.error),
        ),
      ),
    const SizedBox(height: 16),
    Align(
      alignment: AlignmentDirectional.centerStart,
      child: OutlinedButton(
        onPressed: _picking ? null : _changeBackup,
        child: const Text('Change', semanticsLabel: 'Change the backup folder'),
      ),
    ),
  ];

  List<Widget> _switchStep(ThemeData theme) => [
    Semantics(
      header: true,
      child: Text('How the app runs', style: theme.textTheme.headlineSmall),
    ),
    const SizedBox(height: 8),
    const Text('You can change these later in Settings.'),
    const SizedBox(height: 16),
    WatchTile(value: _watch, onChanged: (v) => setState(() => _watch = v)),
    StartAtLoginTile(
      value: _startAtLogin,
      onChanged: (v) => setState(() => _startAtLogin = v),
    ),
  ];
}
