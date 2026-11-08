/// Watch: gathers on its own after the game saved a Memories file.
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:memories_core/memories_core.dart' as core;

import '../gather/gather_controller.dart';
import '../settings/settings_controller.dart';

/// The signature of the Memories files of a flavor folder, or null when it
/// has none or cannot be read now.
typedef SignatureFunction = Future<String?> Function(String flavorDir);

/// Starts a repeating timer, as [Timer.periodic] does.
typedef PeriodicTimer = Timer Function(
  Duration period,
  void Function(Timer timer) callback,
);

/// The signature of `memories_core`.
Future<String?> flavorSignature(String flavorDir) =>
    core.signature(Directory(flavorDir));

/// The state of [WatchController].
enum WatchState {
  /// Watch is off.
  off,

  /// The files are as they were at the last gather, or a failed gather waits
  /// for a change or its one retry.
  idle,

  /// The files changed; Watch waits until they stay the same.
  settling,

  /// Watch runs a gather.
  gathering,
}

/// Polls the signature of the Memories files and gathers once after each
/// change, when the files stayed the same on two polls at least
/// [stableAfter] apart, so it never reads a file that the game still writes.
/// It saves the signature of each gather that passed in the settings, so a
/// restart with no change does not gather.
class WatchController extends ChangeNotifier {
  WatchController({
    required this.settings,
    required this.gather,
    this.signature = flavorSignature,
    this.clock = DateTime.now,
    this.timer = Timer.periodic,
  }) {
    gather.addListener(_onGather);
  }

  static const Duration pollEvery = Duration(seconds: 10);
  static const Duration stableAfter = Duration(seconds: 5);
  static const Duration retryAfter = Duration(minutes: 5);

  final SettingsController settings;
  final GatherController gather;
  final SignatureFunction signature;
  final DateTime Function() clock;
  final PeriodicTimer timer;

  WatchState _state = WatchState.off;
  Timer? _ticker;
  bool _disposed = false;

  /// The run whose poll reads the signature now, so a poll of an earlier run
  /// does not hold back the first poll after [start].
  int? _pollingRun;

  /// Bumped on [start] and [stop], so that a poll or a gather of an earlier
  /// run does not change the state of this one.
  int _run = 0;

  /// The changed signature that [WatchState.settling] waits on, and when it
  /// was first seen.
  String? _pending;
  DateTime? _seenAt;

  /// The signature of the last gather of Watch that failed, and when.
  String? _failed;
  DateTime? _failedAt;
  bool _retryLeft = false;

  bool _ownGather = false;
  bool _gatherWasRunning = false;

  /// The signature taken when a gather that Watch did not start began, such
  /// as one of the Gather now button.
  Future<String?>? _otherGather;
  String? _otherFlavor;

  WatchState get state => _state;

  /// Whether Watch is on.
  bool get watching => _state != WatchState.off;

  /// Starts the polls, with one at once. It does nothing when Watch is on.
  void start() {
    if (watching) return;
    _run++;
    _setState(WatchState.idle);
    _ticker = timer(pollEvery, (_) => poll());
    poll();
  }

  /// Stops the polls. A gather that runs ends as usual.
  void stop() {
    if (!watching) return;
    _run++;
    _ticker?.cancel();
    _ticker = null;
    _pending = null;
    _seenAt = null;
    _failed = null;
    _failedAt = null;
    _retryLeft = false;
    _otherGather = null;
    _setState(WatchState.off);
  }

  /// Takes the signature and moves the state machine one step.
  @visibleForTesting
  Future<void> poll() async {
    if (_pollingRun == _run || _state == WatchState.off) return;
    if (_state == WatchState.gathering) return;
    final flavor = settings.settings.flavorDir;
    if (flavor == null || settings.settings.backupRoot == null) return;
    final run = _run;
    _pollingRun = run;
    String? sig;
    try {
      sig = await signature(flavor);
    } on Object {
      sig = null;
    } finally {
      if (_pollingRun == run) _pollingRun = null;
    }
    // A null signature tells nothing, so the state stays as it is and the
    // next poll asks again.
    if (sig == null || run != _run || settings.settings.flavorDir != flavor) {
      return;
    }
    final now = clock();
    final last = settings.settings.lastSignature;
    switch (_state) {
      case WatchState.idle:
        if (sig == last) {
          _clearFailure();
        } else if (sig != _failed) {
          _clearFailure();
          _settle(sig, now);
        } else if (_retryLeft) {
          // A clock set back would hold the retry for a long time.
          if (now.isBefore(_failedAt!)) _failedAt = now;
          if (now.difference(_failedAt!) >= retryAfter) {
            _retryLeft = false;
            await _runGather(sig);
          }
        }
      case WatchState.settling:
        if (sig == last) {
          _pending = null;
          _seenAt = null;
          _setState(WatchState.idle);
        } else if (sig != _pending || now.isBefore(_seenAt!)) {
          _settle(sig, now);
        } else if (now.difference(_seenAt!) >= stableAfter &&
            !gather.running &&
            _otherGather == null) {
          await _runGather(sig);
        }
      case WatchState.off:
      case WatchState.gathering:
        break;
    }
  }

  void _settle(String sig, DateTime now) {
    _pending = sig;
    _seenAt = now;
    _setState(WatchState.settling);
  }

  void _clearFailure() {
    _failed = null;
    _failedAt = null;
    _retryLeft = false;
  }

  Future<void> _runGather(String sig) async {
    final s = settings.settings;
    final flavor = s.flavorDir!;
    final root = s.backupRoot!;
    final run = _run;
    _setState(WatchState.gathering);
    _ownGather = true;
    core.GatherResult? result;
    try {
      result = await gather.gatherNow(flavorDir: flavor, backupRoot: root);
    } finally {
      _ownGather = false;
    }
    final passed = result != null && result.stop == null;
    // The signature was taken before the gather, so a change during the
    // gather differs from it and the next polls gather again.
    if (passed && !_disposed) _saveSignature(sig, flavor, root);
    if (run != _run) return;
    _pending = null;
    _seenAt = null;
    if (result == null) {
      // Another gather started first; settle again after it.
      _settle(sig, clock());
      return;
    }
    if (passed) {
      _clearFailure();
    } else {
      // A second failure of the same files is the retry, or a gather that
      // waited for another one; either way the one retry is used.
      _retryLeft = _failed != sig;
      _failed = sig;
      _failedAt = clock();
    }
    _setState(WatchState.idle);
  }

  /// Saves [sig] when the settings still name the folders of the gather; a
  /// gather of other folders says nothing about these ones.
  void _saveSignature(String sig, String flavor, String root) {
    final s = settings.settings;
    if (s.flavorDir != flavor || s.backupRoot != root) return;
    if (s.lastSignature == sig) return;
    settings.update(s.copyWith(lastSignature: sig));
  }

  void _onGather() {
    final running = gather.running;
    final began = running && !_gatherWasRunning;
    final ended = !running && _gatherWasRunning;
    _gatherWasRunning = running;
    if (_ownGather || !watching) return;
    final flavor = settings.settings.flavorDir;
    if (began && flavor != null) {
      _otherFlavor = flavor;
      _otherGather = signature(flavor)
          .then<String?>((s) => s, onError: (Object _) => null);
    } else if (ended && _otherGather != null) {
      _endOtherGather(_otherGather!, _otherFlavor!, _run);
    }
  }

  /// A gather that Watch did not start counts as a Watch gather, so Watch
  /// does not gather the same files again after it.
  Future<void> _endOtherGather(
    Future<String?> taken,
    String flavor,
    int run,
  ) async {
    final passed = gather.state == GatherState.done;
    final root = settings.settings.backupRoot;
    final sig = await taken;
    // Until here a poll does not gather, so the files of this gather are not
    // gathered twice.
    if (identical(_otherGather, taken)) _otherGather = null;
    if (!passed || sig == null || root == null || run != _run) return;
    _saveSignature(sig, flavor, root);
    if (_state == WatchState.settling && _pending == sig) {
      _pending = null;
      _seenAt = null;
      _setState(WatchState.idle);
    }
  }

  void _setState(WatchState next) {
    if (next == _state) return;
    _state = next;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    stop();
    gather.removeListener(_onGather);
    super.dispose();
  }
}
