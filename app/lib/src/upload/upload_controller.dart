/// Keeps the state of the website upload for the screens: the registration,
/// the characters on the website and the result of the last upload.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:memories_core/memories_core.dart' hide UploadState;
import 'package:path/path.dart' as p;

import '../gather/gather_controller.dart';
import '../settings/settings_controller.dart';
import '../ui/messages.dart';
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
typedef CharacterName = ({String name, String realm});

/// Uploads after each gather when the Upload switch is on, and does the
/// explicit actions: check, register, request screenshots, remove.
///
/// No method throws: a failure becomes a plain message.
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
  bool _uploading = false;
  bool _checking = false;
  bool _registering = false;
  bool _removing = false;
  bool _requesting = false;
  bool? _lastOk;
  bool _paused = false;
  int _progressDone = 0;
  int _progressTotal = 0;
  DateTime? _lastUpload;
  SyncReport? _lastReport;
  List<RemoteCharacter> _characters = const [];
  String _screenshots = 'none';
  List<String> _issues = const [];
  SiteInfo? _siteInfo;
  String? _siteError;
  String? _registerError;

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

  /// `none`, `pending`, `approved` or `denied`.
  String get screenshots => _screenshots;

  /// How far the running upload is, from 0 to 1, or null when no upload runs
  /// or the number of requests is not known yet.
  double? get progress =>
      _uploading && _progressTotal > 0 ? _progressDone / _progressTotal : null;

  /// The requests of the running upload that are done, and all of them.
  ({int done, int total}) get progressCounts =>
      (done: _progressDone, total: _progressTotal);

  /// Plain messages about the last upload or action.
  List<String> get issues => _issues;

  /// The answer of the last Check, or null.
  SiteInfo? get siteInfo => _siteInfo;

  /// Why the last Check failed, or null.
  String? get siteError => _siteError;

  /// Why the last Register failed, or null.
  String? get registerError => _registerError;

  bool get checking => _checking;
  bool get registering => _registering;
  bool get busy => _uploading || _removing || _requesting;

  /// Whether Upload now can start: no other action runs, and no gather is
  /// writing `latest/`.
  bool get canUploadNow => !busy && gather.state != GatherState.running;

  /// Whether Request screenshots makes sense now.
  bool get canRequestScreenshots =>
      _registered &&
      !_requesting &&
      (_screenshots == 'none' || _screenshots == 'denied');

  String get _siteText => _site ?? settings.settings.site;

  /// The name and realm of the character at the web [path].
  CharacterName describe(String path) {
    final parts = path.split('/');
    if (parts.length == 4) {
      return _gathered('${parts[1]}-${parts[2]}-${parts[3]}') ??
          (name: parts[3], realm: parts[2]);
    }
    return (name: path, realm: 'its realm');
  }

  CharacterName? _gathered(String id) {
    for (final c in gather.snapshot.characters) {
      if (c.id == id) return (name: c.name, realm: c.realm);
    }
    return null;
  }

  CharacterName _describeEntry(String id, String path) =>
      _gathered(id) ??
      (path.isEmpty ? (name: id, realm: 'its realm') : describe(path));

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
    _epoch++;
    _registered = false;
    _fingerprint = null;
    _lastOk = null;
    _paused = false;
    _lastReport = null;
    _lastUpload = null;
    _characters = const [];
    _screenshots = 'none';
    _issues = const [];
    _siteInfo = null;
    _siteError = null;
    _registerError = null;
    _notify();
    unawaited(refresh());
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
    String? error;
    try {
      status = await service.status(site);
    } on UploadException catch (e) {
      // A damaged key file shows here, before the player tries to register.
      status = (registered: false, fingerprint: null);
      error = uploadErrorText(e, site);
    } on Object {
      status = (registered: false, fingerprint: null);
    }
    if (epoch != _epoch || _disposed) return;
    _registerError = error;
    _registered = status.registered;
    _fingerprint = status.fingerprint;
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
        _addIssue(uploadErrorText(e, site));
      }
    } on Object {
      if (epoch != _epoch || _disposed) return;
      _addIssue(genericFailureText);
    }
    _notify();
  }

  /// Keeps the messages of the upload or action that ran just before.
  void _addIssue(String text) {
    if (!_issues.contains(text)) _issues = [..._issues, text];
  }

  /// Saves the address [text] as the website. Returns a plain message when
  /// it is not an address that the app accepts, else null. A new website
  /// starts unregistered with Upload off; the state of the old one is kept.
  String? changeSite(String text) {
    final Uri uri;
    try {
      uri = parseSite(text);
    } on FormatException catch (e) {
      return e.message;
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
    String? error;
    try {
      info = await service.info(site);
      if (info.api != 1 || info.name.isEmpty) {
        info = null;
        error = notAMemoriesSiteText;
      }
    } on UploadException catch (e) {
      error = uploadErrorText(e, site);
    } on Object {
      error = genericFailureText;
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
    if (_registering) return false;
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
    } on UploadException catch (e) {
      if (epoch == _epoch) {
        _registerError = uploadErrorText(e, site);
        if (e.code == 'key_revoked') _setUploadOff();
      }
      return false;
    } on Object {
      if (epoch == _epoch) _registerError = genericFailureText;
      return false;
    } finally {
      _registering = false;
      _notify();
    }
    await _loadMe(site, epoch);
    return true;
  }

  /// Uploads `<backup folder>/latest`. Returns null, and does nothing, while
  /// an upload, a removal or a gather runs, when the key is not registered, or
  /// when the Upload switch is off. The upload after a gather skips the
  /// characters the player removed; the Upload now button passes
  /// [resendRemoved] to send them again.
  Future<SyncReport?> uploadNow({bool resendRemoved = false}) async {
    final s = settings.settings;
    final root = s.backupRoot;
    if (_uploading ||
        _removing ||
        gather.state == GatherState.running ||
        !_registered ||
        !s.upload ||
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
    var issues = <String>[];
    var ok = false;
    var paused = false;
    final keyErrors = <String>{};
    try {
      report = await service.sync(
        site,
        p.join(root, 'latest'),
        resendRemoved: resendRemoved,
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
        issues = [uploadErrorText(e, site)];
        keyErrors.add(e.code);
      }
    } on Object {
      issues = [genericFailureText];
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
    _issues = [keyRevokedText(site)];
    _setUploadOff();
  }

  /// One message for each problem of [report]. A failure that every next
  /// request of the run would get too shows once.
  List<String> _issuesOf(SyncReport report) {
    final site = _siteText;
    final out = <String>[];
    void add(String text) {
      if (!out.contains(text)) out.add(text);
    }

    for (final c in report.characters) {
      final who = _describeEntry(c.id, c.path);
      final e = c.error;
      if (e != null && !e.recoverable) {
        if (stopsRun(e)) {
          add(uploadErrorText(e, site));
        } else if (e.code == 'claimed') {
          add(claimedText(who.name, who.realm));
        } else if (e.code == 'invalid' && e.problems.isNotEmpty) {
          add(rejectedText(who.name, e.problems));
        } else {
          add('${who.name}: ${uploadErrorText(e, site)}');
        }
      }
      for (final m in c.shots.errors.take(3)) {
        add('${who.name}: $m');
      }
      final stop = c.shots.stop;
      if (stop != null && !stop.recoverable && stopsRun(stop)) {
        add(uploadErrorText(stop, site));
      }
    }
    return out;
  }

  /// Removes the character at the web [path] from the website. Returns
  /// whether it is gone.
  Future<bool> removeCharacter(String path) async {
    if (!_registered) return false;
    if (busy) {
      // An upload can start while the confirm dialog is open.
      _issues = const [busyText];
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
          _issues = [uploadErrorText(e, site)];
          _onKeyError(e.code);
        }
      }
    } on Object {
      gone = false;
      if (epoch == _epoch) _issues = const [genericFailureText];
    }
    _removing = false;
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
        _issues = [uploadErrorText(e, site)];
        _onKeyError(e.code);
      }
    } on Object {
      ok = false;
      if (epoch == _epoch) _issues = const [genericFailureText];
    }
    _requesting = false;
    _notify();
    return ok;
  }

  @override
  void dispose() {
    _disposed = true;
    settings.removeListener(_onSettings);
    gather.removeListener(_onGather);
    super.dispose();
  }
}
