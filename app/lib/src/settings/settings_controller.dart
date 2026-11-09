/// Holds the settings in memory for the screens and saves each change.
library;

import 'package:flutter/foundation.dart';

import 'settings.dart';
import 'settings_store.dart';

/// The settings of the app, loaded once and saved on each [update].
class SettingsController extends ChangeNotifier {
  SettingsController(this.store);

  final SettingsStore store;

  Settings _settings = const Settings();
  bool _loaded = false;
  SettingsNotice? _notice;

  Settings get settings => _settings;

  /// Whether [load] has ended.
  bool get loaded => _loaded;

  /// A message for the user about the settings file, or null.
  SettingsNotice? get notice => _notice;

  Future<void> load() async {
    final loaded = await store.load();
    _settings = loaded.settings;
    _notice = loaded.notice;
    _loaded = true;
    notifyListeners();
  }

  /// Saves [next] and uses it. When the save fails, the app keeps [next] for
  /// this run, sets [notice] and returns false.
  Future<bool> update(Settings next) {
    _settings = next;
    notifyListeners();
    // Saves run one after the other, so the file always ends with the newest
    // settings even when two quick changes overlap.
    final save = _saving.then((_) => _save(next));
    _saving = save.then((saved) => saved, onError: (Object _) => false);
    return save;
  }

  Future<bool> _saving = Future.value(true);

  Future<bool> _save(Settings next) async {
    var saved = true;
    try {
      await store.save(next);
    } on Exception {
      saved = false;
    }
    final notice = saved ? null : SettingsNotice.saveFailed;
    if (notice != _notice) {
      _notice = notice;
      notifyListeners();
    }
    return saved;
  }

  void dismissNotice() {
    if (_notice == null) return;
    _notice = null;
    notifyListeners();
  }
}
