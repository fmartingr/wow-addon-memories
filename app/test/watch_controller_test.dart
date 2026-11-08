import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:memories_core/memories_core.dart';
import 'package:wow_journey/src/gather/gather_controller.dart';
import 'package:wow_journey/src/settings/settings.dart';
import 'package:wow_journey/src/settings/settings_controller.dart';
import 'package:wow_journey/src/watch/watch_controller.dart';

import 'support/fakes.dart';

class FakeTimer implements Timer {
  bool cancelled = false;

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
}

GatherReport _failed() => (
  result: GatherResult(issues: [issue(GatherIssueCode.lockHeld, fatal: true)]),
  snapshot: const BackupSnapshot(),
);

GatherReport _passed() =>
    (result: const GatherResult(), snapshot: const BackupSnapshot());

/// A [WatchController] on a real [SettingsController] and
/// [GatherController], with a fake clock, timer, signature and gather.
class Harness {
  Harness({String? last = 'S0', String? current = 'S0'})
    : store = FakeSettingsStore((
        settings: readySettings.copyWith(lastSignature: last),
        notice: null,
      )),
      sig = FakeSignature(current);

  final FakeSettingsStore store;
  final FakeSignature sig;
  final FakeGatherService service = FakeGatherService();
  late final SettingsController settings = SettingsController(store);
  late final GatherController gather = GatherController(service);
  DateTime now = DateTime(2026, 11, 8, 12);
  Duration? period;
  void Function(Timer)? _tick;
  final FakeTimer timer = FakeTimer();
  final List<WatchState> states = [];

  late final WatchController watch = WatchController(
    settings: settings,
    gather: gather,
    signature: sig.call,
    clock: () => now,
    timer: (d, cb) {
      period = d;
      _tick = cb;
      return timer;
    },
  )..addListener(() => states.add(watch.state));

  String? get last => settings.settings.lastSignature;
  int get gathers => service.calls.length;

  Future<void> start() async {
    await settings.load();
    watch.start();
    await pumpEventQueue();
  }

  /// Moves the clock by [by] and fires the poll timer.
  Future<void> tick([Duration by = WatchController.pollEvery]) async {
    now = now.add(by);
    _tick!(timer);
    await pumpEventQueue();
  }

  /// Runs a gather as the Gather now button does.
  Future<GatherResult?> gatherNow() => gather.gatherNow(
    flavorDir: settings.settings.flavorDir!,
    backupRoot: settings.settings.backupRoot!,
  );
}

void main() {
  group('WatchController', () {
    test('polls at once on start, then every 10 s', () async {
      final h = Harness();
      expect(h.watch.state, WatchState.off);
      await h.start();
      expect(h.watch.state, WatchState.idle);
      expect(h.watch.watching, isTrue);
      expect(h.period, const Duration(seconds: 10));
      expect(h.sig.calls, [retailDir]);
      await h.tick();
      expect(h.sig.calls, hasLength(2));
    });

    test('the same signature after a restart does not gather', () async {
      final h = Harness();
      await h.start();
      for (var i = 0; i < 5; i++) {
        await h.tick();
      }
      expect(h.gathers, 0);
      expect(h.states, [WatchState.idle]);
    });

    test('a change settles, gathers once and saves the signature', () async {
      final h = Harness();
      await h.start();
      h.sig.value = 'S1';
      await h.tick();
      expect(h.watch.state, WatchState.settling);
      expect(h.gathers, 0);
      await h.tick();
      expect(h.gathers, 1);
      expect(h.service.calls.single, (retailDir, readySettings.backupRoot!));
      expect(h.watch.state, WatchState.idle);
      expect(h.last, 'S1');
      expect(h.store.saved.last.lastSignature, 'S1');
      for (var i = 0; i < 5; i++) {
        await h.tick();
      }
      expect(h.gathers, 1);
      expect(h.states, [
        WatchState.idle,
        WatchState.settling,
        WatchState.gathering,
        WatchState.idle,
      ]);
    });

    test('no saved signature, as on the first run, gathers', () async {
      final h = Harness(last: null);
      await h.start();
      expect(h.watch.state, WatchState.settling);
      await h.tick();
      expect(h.gathers, 1);
      expect(h.last, 'S0');
    });

    test('two polls less than 5 s apart do not gather', () async {
      final h = Harness();
      await h.start();
      h.sig.value = 'S1';
      await h.tick();
      h.now = h.now.add(const Duration(seconds: 4, milliseconds: 999));
      await h.watch.poll();
      expect(h.gathers, 0);
      expect(h.watch.state, WatchState.settling);
      h.now = h.now.add(const Duration(milliseconds: 1));
      await h.watch.poll();
      expect(h.gathers, 1);
    });

    test(
      'a file that is still written waits until it stays the same',
      () async {
        final h = Harness();
        await h.start();
        for (final s in ['S1', 'S2', 'S3']) {
          h.sig.value = s;
          await h.tick();
          expect(h.watch.state, WatchState.settling);
        }
        expect(h.gathers, 0);
        await h.tick();
        expect(h.gathers, 1);
        expect(h.last, 'S3');
      },
    );

    test('a file back as it was before the gather goes idle', () async {
      final h = Harness();
      await h.start();
      h.sig.value = 'S1';
      await h.tick();
      h.sig.value = 'S0';
      await h.tick();
      expect(h.watch.state, WatchState.idle);
      await h.tick();
      expect(h.gathers, 0);
    });

    test('saves the signature taken before the gather and gathers a change '
        'made during it after it', () async {
      final h = Harness();
      await h.start();
      h.sig.value = 'S1';
      await h.tick();
      h.service.pending = Completer<GatherReport>();
      await h.tick();
      expect(h.watch.state, WatchState.gathering);
      h.sig.value = 'S2';
      final callsBefore = h.sig.calls.length;
      await h.tick();
      expect(h.sig.calls, hasLength(callsBefore), reason: 'no poll now');
      h.service.pending!.complete(_passed());
      h.service.pending = null;
      await pumpEventQueue();
      expect(h.last, 'S1');
      expect(h.watch.state, WatchState.idle);
      await h.tick();
      expect(h.watch.state, WatchState.settling);
      await h.tick();
      expect(h.gathers, 2);
      expect(h.last, 'S2');
    });

    test('a failed gather does not save the signature and retries once '
        'after 5 minutes', () async {
      final h = Harness();
      await h.start();
      h.service.next = _failed();
      h.sig.value = 'S1';
      await h.tick();
      await h.tick();
      expect(h.gathers, 1);
      expect(h.last, 'S0');
      expect(h.watch.state, WatchState.idle);
      for (var i = 0; i < 28; i++) {
        await h.tick();
      }
      expect(h.gathers, 1, reason: '4 min 40 s after the failure');
      await h.tick(const Duration(seconds: 20));
      expect(h.gathers, 2);
      expect(h.last, 'S0');
      for (var i = 0; i < 90; i++) {
        await h.tick();
      }
      expect(h.gathers, 2, reason: 'only one retry');
    });

    test('a retry that passes saves the signature', () async {
      final h = Harness();
      await h.start();
      h.service.next = _failed();
      h.sig.value = 'S1';
      await h.tick();
      await h.tick();
      h.service.next = _passed();
      await h.tick(WatchController.retryAfter);
      expect(h.gathers, 2);
      expect(h.last, 'S1');
    });

    test('a failed gather retries at the next change', () async {
      final h = Harness();
      await h.start();
      h.service.next = _failed();
      h.sig.value = 'S1';
      await h.tick();
      await h.tick();
      h.service.next = _passed();
      h.sig.value = 'S2';
      await h.tick();
      expect(h.watch.state, WatchState.settling);
      await h.tick();
      expect(h.gathers, 2);
      expect(h.last, 'S2');
    });

    test('a failed gather back to the saved signature forgets the '
        'failure', () async {
      final h = Harness();
      await h.start();
      h.service.next = _failed();
      h.sig.value = 'S1';
      await h.tick();
      await h.tick();
      h.sig.value = 'S0';
      await h.tick();
      h.sig.value = 'S1';
      await h.tick();
      expect(h.watch.state, WatchState.settling);
    });

    test('a clock set back while settling gathers 5 s after the new '
        'time', () async {
      final h = Harness();
      await h.start();
      h.sig.value = 'S1';
      await h.tick();
      await h.tick(const Duration(hours: -1));
      expect(h.gathers, 0);
      expect(h.watch.state, WatchState.settling);
      await h.tick();
      expect(h.gathers, 1);
    });

    test('a clock set back after a failure retries 5 min after the new '
        'time', () async {
      final h = Harness();
      await h.start();
      h.service.next = _failed();
      h.sig.value = 'S1';
      await h.tick();
      await h.tick();
      await h.tick(const Duration(days: -1));
      expect(h.gathers, 1);
      await h.tick(WatchController.retryAfter);
      expect(h.gathers, 2);
    });

    test('a signature that cannot be taken changes nothing', () async {
      final h = Harness();
      await h.start();
      h.sig.value = 'S1';
      await h.tick();
      h.sig.value = null;
      await h.tick();
      h.sig
        ..value = 'S1'
        ..error = const FileSystemExceptionFake();
      await h.tick();
      expect(h.watch.state, WatchState.settling);
      expect(h.gathers, 0);
      h.sig.error = null;
      await h.tick();
      expect(h.gathers, 1);
    });

    test('a flavor folder that is gone gives no gather', () async {
      final h = Harness(current: null);
      await h.start();
      for (var i = 0; i < 5; i++) {
        await h.tick();
      }
      expect(h.watch.state, WatchState.idle);
      expect(h.gathers, 0);
    });

    test('never starts a gather while another one runs', () async {
      final h = Harness();
      await h.start();
      h.service.pending = Completer<GatherReport>();
      unawaited(h.gatherNow());
      h.sig.value = 'S1';
      await h.tick();
      await h.tick();
      await h.tick();
      expect(h.gathers, 1);
      expect(h.watch.state, WatchState.settling);
      expect(h.states, isNot(contains(WatchState.gathering)));
      h.service.pending!.complete(_passed());
      h.service.pending = null;
      await pumpEventQueue();
      // The Gather now gather began before the change, so Watch still
      // gathers the change after it.
      expect(h.last, 'S0');
      await h.tick();
      expect(h.gathers, 2);
      expect(h.last, 'S1');
    });

    test('Gather now during settling is not gathered again', () async {
      final h = Harness();
      await h.start();
      h.sig.value = 'S1';
      await h.tick();
      expect(h.watch.state, WatchState.settling);
      await h.gatherNow();
      await pumpEventQueue();
      expect(h.last, 'S1');
      expect(h.watch.state, WatchState.idle);
      for (var i = 0; i < 5; i++) {
        await h.tick();
      }
      expect(h.gathers, 1);
    });

    test('a failed Gather now during settling leaves the change to '
        'Watch', () async {
      final h = Harness();
      await h.start();
      h.sig.value = 'S1';
      await h.tick();
      h.service.next = _failed();
      await h.gatherNow();
      await pumpEventQueue();
      expect(h.last, 'S0');
      h.service.next = _passed();
      await h.tick();
      expect(h.gathers, 2);
      expect(h.last, 'S1');
    });

    test('Gather now with Watch off saves no signature', () async {
      final h = Harness();
      await h.settings.load();
      h.sig.value = 'S1';
      await h.gatherNow();
      await pumpEventQueue();
      expect(h.last, 'S0');
      expect(h.sig.calls, isEmpty);
    });

    test('stop cancels the polls; start sees the change again', () async {
      final h = Harness();
      await h.start();
      h.sig.value = 'S1';
      await h.tick();
      h.watch.stop();
      expect(h.watch.state, WatchState.off);
      expect(h.timer.cancelled, isTrue);
      final calls = h.sig.calls.length;
      await h.watch.poll();
      expect(h.sig.calls, hasLength(calls));
      h.watch.start();
      await pumpEventQueue();
      expect(h.watch.state, WatchState.settling);
      await h.tick();
      expect(h.gathers, 1);
    });

    test('start and stop twice do nothing more', () async {
      final h = Harness();
      await h.start();
      h.watch.start();
      await pumpEventQueue();
      expect(h.sig.calls, hasLength(1));
      h.watch
        ..stop()
        ..stop();
      expect(h.states, [WatchState.idle, WatchState.off]);
    });

    test('a stop during a gather saves its signature and stays off', () async {
      final h = Harness();
      await h.start();
      h.sig.value = 'S1';
      await h.tick();
      h.service.pending = Completer<GatherReport>();
      await h.tick();
      h.watch.stop();
      h.service.pending!.complete(_passed());
      await pumpEventQueue();
      expect(h.watch.state, WatchState.off);
      expect(h.last, 'S1');
    });

    test('a gather of a folder the user changed saves nothing', () async {
      final h = Harness();
      await h.start();
      h.sig.value = 'S1';
      await h.tick();
      h.service.pending = Completer<GatherReport>();
      await h.tick();
      await h.settings.update(
        h.settings.settings.copyWith(flavorDir: foreverDir),
      );
      h.service.pending!.complete(_passed());
      await pumpEventQueue();
      expect(h.last, 'S0');
      expect(h.watch.state, WatchState.idle);
    });

    test('a poll that ends after the folder changed is dropped', () async {
      final h = Harness();
      await h.start();
      final slow = Completer<String?>();
      final watch = WatchController(
        settings: h.settings,
        gather: h.gather,
        signature: (_) => slow.future,
        clock: () => h.now,
        timer: (_, _) => FakeTimer(),
      )..start();
      await h.settings.update(
        h.settings.settings.copyWith(flavorDir: foreverDir),
      );
      slow.complete('S1');
      await pumpEventQueue();
      expect(watch.state, WatchState.idle);
      watch.dispose();
    });

    test('no folders in the settings take no signature', () async {
      final h = Harness();
      h.store.loaded = (settings: const Settings(), notice: null);
      await h.start();
      expect(h.sig.calls, isEmpty);
      expect(h.watch.state, WatchState.idle);
    });

    test('a gather that ends after dispose saves nothing', () async {
      final h = Harness();
      await h.start();
      h.sig.value = 'S1';
      await h.tick();
      h.service.pending = Completer<GatherReport>();
      await h.tick();
      h.watch.dispose();
      h.service.pending!.complete(_passed());
      await pumpEventQueue();
      expect(h.last, 'S0');
      expect(h.store.saved, isEmpty);
    });

    test('a stop and start during a poll polls at once', () async {
      final h = Harness();
      await h.start();
      final slow = Completer<String?>();
      final calls = <String>[];
      final watch = WatchController(
        settings: h.settings,
        gather: h.gather,
        signature: (dir) {
          calls.add(dir);
          return calls.length == 1 ? slow.future : Future.value('S0');
        },
        clock: () => h.now,
        timer: (_, _) => FakeTimer(),
      )..start();
      watch
        ..stop()
        ..start();
      await pumpEventQueue();
      expect(calls, hasLength(2));
      slow.complete('S1');
      await pumpEventQueue();
      expect(watch.state, WatchState.idle);
      watch.dispose();
    });

    test('Gather now that ends before its signature is read is not '
        'gathered again', () async {
      final h = Harness();
      await h.start();
      h.sig.value = 'S1';
      await h.tick();
      expect(h.watch.state, WatchState.settling);
      final slow = Completer<String?>();
      h.sig.held.add(slow);
      await h.gatherNow();
      await h.tick();
      expect(h.gathers, 1, reason: 'no gather before the signature is read');
      slow.complete('S1');
      await pumpEventQueue();
      expect(h.last, 'S1');
      expect(h.watch.state, WatchState.idle);
      await h.tick();
      expect(h.gathers, 1);
    });

    test('a retry that waits for another gather and then fails does not '
        'retry again', () async {
      final h = Harness();
      await h.start();
      h.service.next = _failed();
      h.sig.value = 'S1';
      await h.tick();
      await h.tick();
      expect(h.gathers, 1);
      h.service.pending = Completer<GatherReport>();
      unawaited(h.gatherNow());
      await h.tick(WatchController.retryAfter);
      expect(h.watch.state, WatchState.settling);
      h.service.pending!.complete(_failed());
      h.service.pending = null;
      await pumpEventQueue();
      await h.tick();
      expect(h.gathers, 3);
      for (var i = 0; i < 60; i++) {
        await h.tick();
      }
      expect(h.gathers, 3);
    });

    test('dispose stops the polls and leaves the gather', () async {
      final h = Harness();
      await h.start();
      h.watch.dispose();
      expect(h.timer.cancelled, isTrue);
      await h.gatherNow();
      expect(h.gathers, 1);
    });
  });
}
