import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:memories_core/memories_core.dart';
import 'package:wow_journey/src/gather/gather_controller.dart';
import 'package:wow_journey/src/settings/settings.dart';
import 'package:wow_journey/src/settings/settings_controller.dart';
import 'package:wow_journey/src/shell/shell_controller.dart';
import 'package:wow_journey/src/watch/watch_controller.dart';

import 'support/fakes.dart';

class _Timer implements Timer {
  bool cancelled = false;

  @override
  void cancel() => cancelled = true;

  @override
  bool get isActive => !cancelled;

  @override
  int get tick => 0;
}

/// A [ShellController] on a real settings, gather and Watch controller, with
/// fake services.
class _Shell {
  _Shell({
    Settings settings = readySettings,
    bool trayShows = true,
    bool startHidden = false,
  }) : store = FakeSettingsStore((settings: settings, notice: null)) {
    tray.shows = trayShows;
    shell = ShellController(
      settings: this.settings,
      gather: gather,
      watch: watch,
      tray: tray,
      window: window,
      startup: startup,
      opener: opener,
      startHidden: startHidden,
    );
  }

  final FakeSettingsStore store;
  final FakeGatherService service = FakeGatherService();
  final FakeTray tray = FakeTray();
  final FakeWindow window = FakeWindow();
  final FakeStartup startup = FakeStartup();
  final FakeOpener opener = FakeOpener();
  final _Timer timer = _Timer();
  late final SettingsController settings = SettingsController(store);
  late final GatherController gather = GatherController(service);
  late final WatchController watch = WatchController(
    settings: settings,
    gather: gather,
    signature: FakeSignature('S').call,
    timer: (_, _) => timer,
  );
  late final ShellController shell;

  Future<void> start() async {
    await settings.load();
    await shell.start();
    await pumpEventQueue();
  }
}

void main() {
  group('startsHidden', () {
    test('is true only with --hidden', () {
      expect(startsHidden(['--hidden']), isTrue);
      expect(startsHidden(['--other', '--hidden']), isTrue);
      expect(startsHidden([]), isFalse);
      expect(startsHidden(['--hidden=false', '-hidden', 'hidden']), isFalse);
    });
  });

  group('the close button', () {
    test('hides the window when the tray shows', () async {
      final h = _Shell();
      await h.start();
      await h.window.close();
      expect(h.window.calls, ['init', 'hide']);
      expect(h.tray.disposed, isFalse);
    });

    test('quits when there is no tray', () async {
      final h = _Shell(trayShows: false);
      await h.start();
      h.watch.start();
      await h.window.close();
      expect(h.window.calls, ['init', 'quit']);
      expect(h.watch.watching, isFalse);
    });
  });

  group('the tray menu', () {
    test('has the four items in order', () async {
      final h = _Shell();
      await h.start();
      expect(h.tray.items.map((i) => i.label), [
        'Gather now',
        'Open window',
        'Open backup folder',
        'Quit',
      ]);
    });

    test('Gather now gathers and leaves a hidden window hidden', () async {
      final h = _Shell(startHidden: true);
      await h.start();
      h.service.pending = Completer();
      h.tray.select(TrayLabels.gatherNow);
      await pumpEventQueue();
      expect(h.service.calls, [(retailDir, readySettings.backupRoot!)]);
      expect(h.gather.running, isTrue);
      h.service.pending!.complete((
        result: const GatherResult(),
        snapshot: const BackupSnapshot(),
      ));
      await pumpEventQueue();
      expect(h.gather.state, GatherState.done);
      expect(h.window.calls, ['init']);
    });

    test('Gather now before the wizard ends shows the window', () async {
      final h = _Shell(settings: const Settings());
      await h.start();
      h.window.calls.clear();
      h.tray.select(TrayLabels.gatherNow);
      await pumpEventQueue();
      expect(h.service.calls, isEmpty);
      expect(h.window.calls, ['show']);
    });

    test('Open window shows the window', () async {
      final h = _Shell();
      await h.start();
      h.tray.select(TrayLabels.openWindow);
      await pumpEventQueue();
      expect(h.window.calls, ['init', 'show']);
    });

    test('Open backup folder opens the backup root', () async {
      final h = _Shell();
      await h.start();
      h.tray.select(TrayLabels.openBackupFolder);
      await pumpEventQueue();
      expect(h.opener.opened, [readySettings.backupRoot]);
      expect(h.window.calls, ['init']);
    });

    test('Open backup folder shows the window when it cannot open', () async {
      final h = _Shell();
      await h.start();
      h.opener.result = false;
      h.tray.select(TrayLabels.openBackupFolder);
      await pumpEventQueue();
      expect(h.window.calls, ['init', 'show']);
    });

    test('Quit stops Watch, removes the icon and quits', () async {
      final h = _Shell();
      await h.start();
      h.watch.start();
      expect(h.watch.watching, isTrue);
      h.tray.select(TrayLabels.quit);
      await pumpEventQueue();
      expect(h.watch.watching, isFalse);
      expect(h.timer.cancelled, isTrue);
      expect(h.tray.disposed, isTrue);
      expect(h.window.calls, ['init', 'quit']);
    });
  });

  group('a hidden start', () {
    test('stays hidden when the wizard is done and the tray shows', () async {
      final h = _Shell(startHidden: true);
      await h.start();
      expect(h.window.calls, ['init']);
    });

    test('shows the window for the wizard', () async {
      final h = _Shell(settings: const Settings(), startHidden: true);
      await h.start();
      expect(h.window.calls, ['init', 'show']);
    });

    test('shows the window when there is no tray', () async {
      final h = _Shell(trayShows: false, startHidden: true);
      await h.start();
      expect(h.window.calls, ['init', 'show']);
    });

    test('waits for the settings before it decides', () async {
      final h = _Shell(settings: const Settings(), startHidden: true);
      await h.shell.start();
      expect(h.window.calls, ['init']);
      await h.settings.load();
      await pumpEventQueue();
      expect(h.window.calls, ['init', 'show']);
    });
  });

  test('a normal start never shows or hides the window', () async {
    final h = _Shell(settings: const Settings(), trayShows: false);
    await h.start();
    expect(h.window.calls, ['init']);
  });

  group('the login entry', () {
    test('is written again at a start with Start at login on', () async {
      final h = _Shell();
      await h.start();
      expect(h.startup.applied, [true]);
    });

    test('is left alone at a start with Start at login off', () async {
      final h = _Shell(settings: readySettings.copyWith(startAtLogin: false));
      await h.start();
      expect(h.startup.applied, isEmpty);
    });

    test('is not written before the wizard ends', () async {
      final h = _Shell(settings: const Settings());
      await h.start();
      expect(h.startup.applied, isEmpty);
    });

    test('follows the switch', () async {
      final h = _Shell();
      await h.start();
      await h.settings.update(
        h.settings.settings.copyWith(startAtLogin: false),
      );
      await h.settings.update(h.settings.settings.copyWith(watch: false));
      await h.settings.update(h.settings.settings.copyWith(startAtLogin: true));
      expect(h.startup.applied, [true, false, true]);
    });
  });
}
