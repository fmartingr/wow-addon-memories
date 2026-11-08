import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wow_journey/src/platform/startup_service.dart';
import 'package:wow_journey/src/platform/tray_service.dart';

/// Answers each program with its entry of [results]; a missing one is not
/// installed.
class _Runner {
  _Runner(this.results);

  final Map<String, ProcessResult> results;
  final List<String> ran = [];

  Future<ProcessResult> call(String exe, List<String> args) async {
    ran.add(exe);
    final r = results[exe];
    if (r == null) throw ProcessException(exe, args, 'not found', 2);
    return r;
  }
}

ProcessResult _result(int code, String out) => ProcessResult(1, code, out, '');

void main() {
  group('hasStatusNotifierHost', () {
    test('is true when gdbus says a host is registered', () async {
      final run = _Runner({'gdbus': _result(0, '(<true>,)\n')});
      expect(await hasStatusNotifierHost(run: run.call), isTrue);
      expect(run.ran, ['gdbus']);
    });

    test('is false when no host is registered', () async {
      final run = _Runner({'gdbus': _result(0, '(<false>,)\n')});
      expect(await hasStatusNotifierHost(run: run.call), isFalse);
    });

    test('is false when no watcher runs, as on GNOME without the '
        'AppIndicator extension', () async {
      final run = _Runner({
        'gdbus': _result(1, ''),
        'busctl': _result(0, 'b true\n'),
      });
      expect(await hasStatusNotifierHost(run: run.call), isFalse);
      expect(run.ran, ['gdbus']);
    });

    test('asks busctl when gdbus is not installed', () async {
      final run = _Runner({'busctl': _result(0, 'b true\n')});
      expect(await hasStatusNotifierHost(run: run.call), isTrue);
      expect(run.ran, ['gdbus', 'busctl']);
    });

    test('is false when neither tool is installed', () async {
      final run = _Runner({});
      expect(await hasStatusNotifierHost(run: run.call), isFalse);
    });
  });

  group('the Linux login entry', () {
    test('quotes the path', () {
      expect(
        desktopExecArgument('/home/me/WoW Journey/wow_journey'),
        '"/home/me/WoW Journey/wow_journey"',
      );
    });

    test('escapes the characters a desktop entry reserves', () {
      expect(desktopExecArgument(r'/a"b'), r'"/a\\"b"');
      expect(desktopExecArgument(r'/a$b`c'), r'"/a\\$b\\`c"');
      expect(desktopExecArgument(r'/a\b'), r'"/a\\\\b"');
      expect(desktopExecArgument('/100%'), '"/100%%"');
    });

    test('refuses a path with a line break', () async {
      final service = SystemStartupService(
        executable: '/a\nExec=/bin/evil',
        operatingSystem: 'linux',
        home: '/nowhere',
      );
      expect(await service.apply(true), isFalse);
    });
  });

  group('the macOS launch agent', () {
    late Directory home;

    setUp(() {
      home = Directory.systemTemp.createTempSync('wow_journey_home_');
    });

    tearDown(() => home.deleteSync(recursive: true));

    File agent() => File(
      p.join(home.path, 'Library', 'LaunchAgents', '$macBundleId.plist'),
    );

    SystemStartupService service(String exe) => SystemStartupService(
      executable: exe,
      operatingSystem: 'macos',
      home: home.path,
    );

    test('starts the app hidden at login', () async {
      const exe = '/Applications/WoW Journey.app/Contents/MacOS/wow_journey';
      expect(await service(exe).apply(true), isTrue);
      final text = agent().readAsStringSync();
      expect(text, contains('<string>$exe</string>'));
      expect(text, contains('<string>--hidden</string>'));
      expect(text, contains('<key>RunAtLoad</key>\n  <true/>'));
      expect(text, contains('<string>$macBundleId</string>'));
    });

    test('is written again with a new app path', () async {
      await service('/old/wow_journey').apply(true);
      await service('/new/wow_journey').apply(true);
      final text = agent().readAsStringSync();
      expect(text, contains('/new/wow_journey'));
      expect(text, isNot(contains('/old/')));
      expect(agent().parent.listSync().map((e) => p.basename(e.path)), [
        '$macBundleId.plist',
      ]);
    });

    test('escapes the path for XML', () {
      expect(
        launchAgentPlist('/A&B/<x>'),
        contains('<string>/A&amp;B/&lt;x&gt;</string>'),
      );
    });

    test('is removed when the switch is off', () async {
      await service('/a/wow_journey').apply(true);
      expect(await service('/a/wow_journey').apply(false), isTrue);
      expect(agent().existsSync(), isFalse);
      expect(await service('/a/wow_journey').apply(false), isTrue);
    });
  });

  test('another system has no login entry', () async {
    final service = SystemStartupService(
      executable: '/a',
      operatingSystem: 'fuchsia',
      home: '/nowhere',
    );
    expect(await service.apply(true), isFalse);
  });
}
