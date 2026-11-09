/// Keeps the state of the website upload for the screens: the registration,
/// the characters on the website and the result of the last upload.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:memories_core/memories_core.dart' hide UploadState;
import 'package:path/path.dart' as p;

import '../gather/gather_controller.dart';
import '../settings/settings_controller.dart';
import 'notice.dart';
import 'upload_service.dart';

/// The state of [UploadController].
enum UploadState {
  /// The key is registered and the Upload switch is off.
  off,

  /// The key is not registered on the website of the settings.
  unregistered,

  /// Upload is on and waits for the next gather.
  idle,

  /// An upload runs.
  uploading,

  /// The last upload ended with no problem.
  done,

  /// The last upload had a problem. The next gather tries again.
  failed,

  /// The website stayed busy for a long time, so the upload stopped with part
  /// of the data unsent. It is no error: the next gather or Upload now sends
  /// the rest.
  paused,
}

/// A character as the screens name it.
typedef CharacterName = ({String name, String? realm});

/// A character of the backup folder with the player's choice to upload it and
/// its page on the website, when it has one.
@immutable
class LocalCharacter {
  const LocalCharacter({
    required this.summary,
    required this.selected,
    this.remote,
  });

  final CharacterSummary summary;

  /// Whether the player chose to upload this character.
  final bool selected;

  /// The page of the character on the website, or null when it has none.
  final RemoteCharacter? remote;
}

/// Uploads after each gather when the Upload switch is on, and does the
/// explicit actions: check, register, request screenshots, remove.
///
/// No method throws: a failure becomes a [Notice].
class UploadController extends ChangeNotifier {
  UploadController({
    required this.service,
    required this.settings,
    required this.gather,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    settings.addListener(_onSettings);
    gather.addListener(_onGather);
    _lastGather = gather.state;
    _onSettings();
  }

  final UploadService service;
  final SettingsController settings;
  final GatherController gather;
  final DateTime Function() _clock;

  String? _site;
  bool _disposed = false;

  /// Counts the sites seen, so the answer of a request for an earlier site is
  /// dropped.
  int _epoch = 0;
  GatherState _lastGather = GatherState.idle;

  bool _registered = false;
  String? _fingerprint;
  Set<String> _selected = {};
  Future<void> _selectionWrite = Future.value();
  bool _uploading = false;
  bool _checking = false;
  bool _registering = false;
  bool _removing = false;
  bool _requesting = false;
  bool _replacing = false;
  bool? _lastOk;
  bool _paused = false;
  int _progressDone = 0;
  int _progressTotal = 0;
  DateTime? _lastUpload;
  SyncReport? _lastReport;
  List<RemoteCharacter> _characters = const [];
  String _screenshots = 'none';
  List<Notice> _issues = const [];
  SiteInfo? _siteInfo;
  Notice? _siteError;
  Notice? _registerError;
  Notice? _keyError;

  UploadState get state {
    if (_uploading) return UploadState.uploading;
    if (!_registered) return UploadState.unregistered;
    if (!settings.settings.upload) return UploadState.off;
    if (_paused) return UploadState.paused;
    return switch (_lastOk) {
      true => UploadState.done,
      false => UploadState.failed,
      null => UploadState.idle,
    };
  }

  /// Whether the key is registered on the website of the settings.
  bool get registered => _registered;

  /// The first 16 hex characters of the SHA-256 of the public key, or null
  /// before the app made a key.
  String? get fingerprint => _fingerprint;

  /// The end of the last upload of this run.
  DateTime? get lastUpload => _lastUpload;

  /// What the last upload did, or null before the first upload of this run.
  SyncReport? get lastReport => _lastReport;

  /// The characters that the website holds for the key.
  List<RemoteCharacter> get characters => _characters;

  /// The characters of the backup folder, each with its choice and its page.
  /// A character that was just gathered is not selected.
  List<LocalCharacter> get localCharacters {
    final pages = {for (final c in _characters) c.path: c};
    return [
      for (final c in gather.snapshot.characters)
        if (c.path.isNotEmpty)
          LocalCharacter(
            summary: c,
            selected: _selected.contains(c.path),
            remote: pages[c.path],
          ),
    ];
  }

  /// The characters on the website that the backup folder does not hold.
  List<RemoteCharacter> get remoteOnlyCharacters {
    final local = {for (final c in gather.snapshot.characters) c.path};
    return [
      for (final c in _characters)
        if (!local.contains(c.path)) c,
    ];
  }

  /// Whether at least one character of the backup folder is selected.
  bool get hasSelection => localCharacters.any((c) => c.selected);

  /// `none`, `pending`, `approved` or `denied`.
  String get screenshots => _screenshots;

  /// How far the running upload is, from 0 to 1, or null when no upload runs
  /// or the number of requests is not known yet.
  double? get progress =>
      _uploading && _progressTotal > 0 ? _progressDone / _progressTotal : null;

  /// The requests of the running upload that are done, and all of them.
  ({int done, int total}) get progressCounts =>
      (done: _progressDone, total: _progressTotal);

  /// The problems of the last upload or action.
  List<Notice> get issues => _issues;

  /// The answer of the last Check, or null.
  SiteInfo? get siteInfo => _siteInfo;

  /// Why the last Check failed, or null.
  Notice? get siteError => _siteError;

  /// Why the last Register failed, or null.
  Notice? get registerError => _registerError;

  /// Why the last Make a new key failed, or null. A wait notice shows only
  /// while the other action still runs.
  Notice? get keyError =>
      _keyError is BusyNotice && !busy && !_registering ? null : _keyError;

  bool get checking => _checking;
  bool get registering => _registering;
  bool get replacing => _replacing;
  bool get busy => _uploading || _removing || _requesting || _replacing;

  /// Whether Make a new key can start now: the app has a key, and no other
  /// action uses it.
  bool get canReplaceKey => _fingerprint != null && !_registering && !busy;

  /// Whether Upload now can start: no other action runs, no gather is writing
  /// `latest/`, and the player selected a character.
  bool get canUploadNow =>
      !busy && gather.state != GatherState.running && hasSelection;

  /// Whether Request screenshots makes sense now.
  bool get canRequestScreenshots =>
      _registered &&
      !_requesting &&
      !_replacing &&
      (_screenshots == 'none' || _screenshots == 'denied');

  String get _siteText => _site ?? settings.settings.site;

  /// The name and realm of the character at the web [path].
  CharacterName describe(String path) {
    final parts = path.split('/');
    if (parts.length == 4) {
      return _gathered('${parts[1]}-${parts[2]}-${parts[3]}') ??
          (name: parts[3], realm: parts[2]);
    }
    return (name: path, realm: null);
  }

  CharacterName? _gathered(String id) {
    for (final c in gather.snapshot.characters) {
      if (c.id == id) return (name: c.name, realm: c.realm);
    }
    return null;
  }

  CharacterName _describeEntry(String id, String path) =>
      _gathered(id) ??
      (path.isEmpty ? (name: id, realm: null) : describe(path));

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _onSettings() {
    if (!settings.loaded) return;
    final site = settings.settings.site;
    if (site == _site) {
      _notify();
      return;
    }
    _site = site;
    _forgetSite();
    _fingerprint = null;
    _siteInfo = null;
    _siteError = null;
    _notify();
    unawaited(refresh());
  }

  /// Drops what the app knows of the key on the website, and the answers of
  /// the requests that still run.
  void _forgetSite() {
    _epoch++;
    _registered = false;
    _selected = {};
    _lastOk = null;
    _paused = false;
    _lastReport = null;
    _lastUpload = null;
    _characters = const [];
    _screenshots = 'none';
    _issues = const [];
    _registerError = null;
    _keyError = null;
  }

  void _onGather() {
    final was = _lastGather;
    _lastGather = gather.state;
    if (gather.state == GatherState.done && was == GatherState.running) {
      unawaited(uploadNow());
    }
    if (gather.state != was) _notify();
  }

  /// Follows an answer about the key itself: a blocked key turns Upload off,
  /// and a key the website no longer knows shows Register again.
  void _onKeyError(String code) {
    if (code == 'key_revoked') _setUploadOff();
    if (code == 'not_registered') _registered = false;
  }

  /// Reads the registration of the key, and the characters of the website
  /// when it is registered.
  Future<void> refresh() async {
    if (!settings.loaded) return;
    final site = _siteText;
    final epoch = _epoch;
    SiteStatus status;
    Notice? error;
    const none = (registered: false, fingerprint: null, selected: <String>{});
    try {
      status = await service.status(site);
    } on UploadException catch (e) {
      // A damaged key file shows here, before the player tries to register.
      status = none;
      error = UploadErrorNotice.of(e, site);
    } on Object {
      status = none;
    }
    if (epoch != _epoch || _disposed) return;
    _registerError = error;
    _registered = status.registered;
    _fingerprint = status.fingerprint;
    _selected = {...status.selected};
    _notify();
    if (_registered) await _loadMe(site, epoch);
  }

  Future<void> _loadMe(String site, int epoch) async {
    try {
      final me = await service.me(site);
      if (epoch != _epoch || _disposed) return;
      _characters = me.characters;
      _screenshots = me.screenshots;
    } on UploadException catch (e) {
      if (epoch != _epoch || _disposed) return;
      if (e.code == 'key_revoked') {
        _revoked(site);
      } else if (!e.recoverable) {
        _onKeyError(e.code);
        _addIssue(UploadErrorNotice.of(e, site));
      }
    } on Object {
      if (epoch != _epoch || _disposed) return;
      _addIssue(const GenericFailureNotice());
    }
    _notify();
  }

  /// Keeps the messages of the upload or action that ran just before.
  void _addIssue(Notice notice) {
    if (!_issues.contains(notice)) _issues = [..._issues, notice];
  }

  /// Saves the address [text] as the website. Returns why when it is not an
  /// address that the app accepts, else null. A new website starts
  /// unregistered with Upload off; the state of the old one is kept.
  Notice? changeSite(String text) {
    final Uri uri;
    try {
      uri = parseSite(text);
    } on SiteFormatException catch (e) {
      return SiteAddressNotice(e.error);
    }
    final next = uri.toString();
    final current = settings.settings.site;
    if (next != current) {
      // A saved address in another spelling, such as a build default with a
      // trailing "/", is the same website: its Upload switch stays.
      final sameSite = _normalized(current) == next;
      settings.update(
        settings.settings.copyWith(site: next, upload: sameSite ? null : false),
      );
    }
    return null;
  }

  static String? _normalized(String site) {
    try {
      return parseSite(site).toString();
    } on FormatException {
      return null;
    }
  }

  /// Asks the website about itself and keeps the answer in [siteInfo] or
  /// [siteError].
  Future<void> checkSite() async {
    if (_checking) return;
    final site = _siteText;
    final epoch = _epoch;
    _checking = true;
    _siteInfo = null;
    _siteError = null;
    _notify();
    SiteInfo? info;
    Notice? error;
    try {
      info = await service.info(site);
      if (info.api != 1 || info.name.isEmpty) {
        info = null;
        error = const NotAMemoriesSiteNotice();
      }
    } on UploadException catch (e) {
      error = UploadErrorNotice.of(e, site);
    } on Object {
      error = const GenericFailureNotice();
    }
    _checking = false;
    if (epoch == _epoch) {
      _siteInfo = info;
      _siteError = error;
    }
    _notify();
  }

  /// Registers the key on the website, with the [invite] code when the
  /// website asks for one. Returns whether it worked.
  Future<bool> register(String? invite) async {
    if (_registering || _replacing) return false;
    final site = _siteText;
    final epoch = _epoch;
    _registering = true;
    _registerError = null;
    _notify();
    try {
      await service.register(site, invite?.trim());
      final status = await service.status(site);
      if (epoch != _epoch) return false;
      _registered = true;
      _fingerprint = status.fingerprint;
      _selected = {...status.selected};
    } on UploadException catch (e) {
      if (epoch == _epoch) {
        _registerError = UploadErrorNotice.of(e, site);
        if (e.code == 'key_revoked') _setUploadOff();
      }
      return false;
    } on Object {
      if (epoch == _epoch) _registerError = const GenericFailureNotice();
      return false;
    } finally {
      _registering = false;
      _notify();
    }
    await _loadMe(site, epoch);
    return true;
  }

  /// Uploads the selected characters of `<backup folder>/latest`. Returns
  /// null, and does nothing, while an upload, a removal or a gather runs, when
  /// the key is not registered, when the Upload switch is off, or when no
  /// character is selected.
  Future<SyncReport?> uploadNow() async {
    final s = settings.settings;
    final root = s.backupRoot;
    if (_uploading ||
        _removing ||
        _replacing ||
        gather.state == GatherState.running ||
        !_registered ||
        !s.upload ||
        !hasSelection ||
        root == null) {
      return null;
    }
    final site = _siteText;
    final epoch = _epoch;
    _uploading = true;
    _issues = const [];
    _progressDone = 0;
    _progressTotal = 0;
    _notify();
    SyncReport? report;
    var issues = <Notice>[];
    var ok = false;
    var paused = false;
    final keyErrors = <String>{};
    try {
      report = await service.sync(
        site,
        p.join(root, 'latest'),
        {..._selected},
        onProgress: (done, total) {
          if (epoch != _epoch || _disposed) return;
          if (done == _progressDone && total == _progressTotal) return;
          _progressDone = done;
          _progressTotal = total;
          _notify();
        },
      );
      issues = _issuesOf(report);
      ok = !report.failed;
      paused = report.paused;
      for (final c in report.characters) {
        if (c.error case final e?) keyErrors.add(e.code);
        if (c.shots.stop case final e?) keyErrors.add(e.code);
      }
    } on UploadException catch (e) {
      if (e.recoverable) {
        paused = true;
      } else {
        issues = [UploadErrorNotice.of(e, site)];
        keyErrors.add(e.code);
      }
    } on Object {
      issues = const [GenericFailureNotice()];
    }
    _uploading = false;
    _progressDone = 0;
    _progressTotal = 0;
    if (epoch != _epoch || _disposed) {
      _notify();
      return report;
    }
    _issues = issues;
    _lastOk = ok;
    _paused = paused;
    _lastReport = report;
    if (report != null && !paused) _lastUpload = _clock();
    if (report != null) _screenshots = report.screenshots;
    keyErrors.forEach(_onKeyError);
    _notify();
    if (report != null && _registered) await _loadMe(site, epoch);
    return report;
  }

  void _setUploadOff() {
    if (_disposed) return;
    if (settings.settings.upload) {
      settings.update(settings.settings.copyWith(upload: false));
    }
  }

  void _revoked(String site) {
    _issues = [UploadErrorNotice('key_revoked', '', site)];
    _setUploadOff();
  }

  /// One notice for each problem of [report]. A failure that every next
  /// request of the run would get too shows once.
  List<Notice> _issuesOf(SyncReport report) {
    final site = _siteText;
    final out = <Notice>[];
    void add(Notice notice) {
      if (!out.contains(notice)) out.add(notice);
    }

    for (final c in report.characters) {
      final who = _describeEntry(c.id, c.path);
      final e = c.error;
      if (e != null && !e.recoverable) {
        if (stopsRun(e)) {
          add(UploadErrorNotice.of(e, site));
        } else if (e.code == 'claimed') {
          add(ClaimedNotice(who.name, who.realm));
        } else if (e.code == 'invalid' && e.problems.isNotEmpty) {
          add(_rejected(who.name, e.problems));
        } else {
          add(UploadErrorNotice.of(e, site, who: who.name));
        }
      }
      for (final m in c.shots.errors.take(3)) {
        add(TextNotice('${who.name}: $m'));
      }
      final stop = c.shots.stop;
      if (stop != null && !stop.recoverable && stopsRun(stop)) {
        add(UploadErrorNotice.of(stop, site));
      }
    }
    return out;
  }

  /// The first 3 problems of a rejected upload, in the English of the website.
  RejectedNotice _rejected(String name, List<UploadProblem> problems) {
    final shown = problems.take(3).map((p) => p.toString()).join('; ');
    return RejectedNotice(
      name,
      shown.endsWith('.') ? shown : '$shown.',
      problems.length > 3 ? problems.length - 3 : 0,
    );
  }

  /// Ticks or unticks the character at the web [path], and saves the choice
  /// at once. Unticking only stops later uploads; the website keeps the page.
  Future<void> setCharacterSelected(String path, bool selected) {
    if (!_registered) return Future.value();
    if (selected ? !_selected.add(path) : !_selected.remove(path)) {
      return Future.value();
    }
    return _selectionChanged();
  }

  /// Selects every character of the backup folder.
  Future<void> selectAll() {
    if (!_registered) return Future.value();
    _selected.addAll(
      gather.snapshot.characters.map((c) => c.path).where((p) => p.isNotEmpty),
    );
    return _selectionChanged();
  }

  /// Unselects every character of the backup folder.
  Future<void> selectNone() {
    if (!_registered) return Future.value();
    _selected.removeAll(gather.snapshot.characters.map((c) => c.path));
    return _selectionChanged();
  }

  /// Shows the new choice now, and writes it after the writes before it.
  Future<void> _selectionChanged() {
    _notify();
    final site = _siteText;
    final epoch = _epoch;
    final choice = {..._selected};
    return _selectionWrite = _selectionWrite.then((_) async {
      Notice? issue;
      try {
        await service.setSelected(site, choice);
      } on UploadException catch (e) {
        issue = UploadErrorNotice.of(e, site);
      } on Object {
        issue = const GenericFailureNotice();
      }
      if (issue != null && epoch == _epoch && !_disposed) {
        _addIssue(issue);
        _notify();
      }
    });
  }

  /// Removes the character at the web [path] from the website and unselects
  /// it. Returns whether it is gone.
  Future<bool> removeCharacter(String path) async {
    if (!_registered) return false;
    if (busy) {
      // An upload can start while the confirm dialog is open.
      _issues = const [BusyNotice()];
      _notify();
      return false;
    }
    final site = _siteText;
    final epoch = _epoch;
    _removing = true;
    _issues = const [];
    _notify();
    var gone = true;
    try {
      await service.delete(site, path);
    } on UploadException catch (e) {
      // 404: the website no longer has it, which is what the player wants.
      // bad_state: the website deleted it; only the local record failed.
      if (e.code != 'not_found') {
        if (e.code != 'bad_state') gone = false;
        if (epoch == _epoch) {
          _issues = [UploadErrorNotice.of(e, site)];
          _onKeyError(e.code);
        }
      }
    } on Object {
      gone = false;
      if (epoch == _epoch) _issues = const [GenericFailureNotice()];
    }
    _removing = false;
    if (gone && epoch == _epoch) _selected.remove(path);
    _notify();
    if (gone) await _loadMe(site, epoch);
    return gone;
  }

  /// Asks the website to approve screenshots. Returns whether it worked.
  Future<bool> requestScreenshots() async {
    if (!canRequestScreenshots) return false;
    final site = _siteText;
    final epoch = _epoch;
    _requesting = true;
    _notify();
    var ok = true;
    try {
      final state = await service.requestScreenshots(site);
      if (epoch == _epoch && state.isNotEmpty) _screenshots = state;
    } on UploadException catch (e) {
      ok = false;
      if (epoch == _epoch) {
        _issues = [UploadErrorNotice.of(e, site)];
        _onKeyError(e.code);
      }
    } on Object {
      ok = false;
      if (epoch == _epoch) _issues = const [GenericFailureNotice()];
    }
    _requesting = false;
    _notify();
    return ok;
  }

  /// Makes a new key in place of the one that the website blocked or
  /// refused. The app is then registered nowhere, with Upload off, so the
  /// player registers again and the app sends everything again. Returns
  /// whether it worked; after a failure the old key stays.
  Future<bool> replaceKey() async {
    if (!canReplaceKey) {
      // An upload can start while the confirm dialog is open.
      if (busy || _registering) {
        _keyError = const BusyNotice();
        _notify();
      }
      return false;
    }
    final site = _siteText;
    _replacing = true;
    _keyError = null;
    _notify();
    var changed = true;
    try {
      final fingerprint = await service.replaceKey();
      if (_disposed) return true;
      _forgetSite();
      _fingerprint = fingerprint;
      _setUploadOff();
      return true;
    } on UploadException catch (e) {
      _keyError = UploadErrorNotice.of(e, site);
      // A failure before any write (no key, a damaged key) changed nothing.
      changed = e.code == 'key_not_replaced';
    } on Object {
      _keyError = const GenericFailureNotice();
    } finally {
      _replacing = false;
      _notify();
    }
    // A failure late in the change can leave the old key unregistered here.
    if (changed) await refresh();
    return false;
  }

  @override
  void dispose() {
    _disposed = true;
    settings.removeListener(_onSettings);
    gather.removeListener(_onGather);
    super.dispose();
  }
}
