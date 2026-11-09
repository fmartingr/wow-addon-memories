/// Reads and writes `settings.json` in the support folder of the app.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'settings.dart';

/// A message about the settings file. The screens turn it into text in the
/// language of the app.
enum SettingsNotice {
  /// The file could not be read, so the app started with the defaults.
  damaged,

  /// The file could not be written.
  saveFailed,
}

/// The settings that [SettingsStore.load] read, and a notice for the user
/// when the file could not be used.
typedef LoadedSettings = ({Settings settings, SettingsNotice? notice});

/// Where the settings live.
abstract interface class SettingsStore {
  /// The saved settings. A missing file gives the defaults and no notice; a
  /// damaged one gives the defaults and a notice. It never throws.
  Future<LoadedSettings> load();

  /// Saves [settings]. Throws a [FileSystemException] when it cannot.
  Future<void> save(Settings settings);
}

/// Keeps the settings in `<dir>/settings.json`.
class FileSettingsStore implements SettingsStore {
  FileSettingsStore(this.directory);

  /// The folder of the settings file, such as the application support folder.
  final Future<String> Function() directory;

  static final Random _random = Random();

  Future<File> _file() async =>
      File(p.join(await directory(), 'settings.json'));

  @override
  Future<LoadedSettings> load() async {
    String? text;
    try {
      final file = await _file();
      if (await file.exists()) text = await file.readAsString();
    } on Exception {
      return (settings: const Settings(), notice: SettingsNotice.damaged);
    }
    if (text == null) return (settings: const Settings(), notice: null);
    try {
      return (settings: Settings.fromJson(jsonDecode(text)), notice: null);
    } on FormatException {
      return (settings: const Settings(), notice: SettingsNotice.damaged);
    }
  }

  @override
  Future<void> save(Settings settings) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final text =
        '${const JsonEncoder.withIndent('  ').convert(settings.toJson())}\n';
    // A crash during the write leaves the old file whole, never half of one.
    final tmp = File(
      p.join(file.parent.path, '.settings-${_random.nextInt(1 << 32)}.tmp'),
    );
    try {
      await tmp.writeAsString(text, flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
  }
}
