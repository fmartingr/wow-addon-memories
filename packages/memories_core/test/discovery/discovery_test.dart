import 'dart:io';

import 'package:memories_core/memories_core.dart';
import 'package:memories_core/src/discovery/candidates.dart'
    show installCandidates;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fixture.dart';

typedef Runner = Future<ProcessOutput?> Function(
  String executable,
  List<String> args,
);

/// Poses as another system. Its paths live in a temporary folder: `C:\x` is
/// `<root>/C/x` and `/x` is `<root>/x`, so the tests use real files and links.
class FakeEnvironment extends Environment {
  FakeEnvironment(
    String root,
    this.operatingSystem, {
    this.env = const {},
    this.run,
  }) : root = Directory(root).resolveSymbolicLinksSync();

  final String root;
  final Runner? run;
  final List<List<String>> calls = [];

  @override
  final String operatingSystem;

  @override
  final Map<String, String> env;

  bool get _windows => operatingSystem == 'windows';

  /// The real path of a path of the posed system.
  String real(String path) {
    final parts = pathContext.split(path);
    return p.joinAll([
      root,
      if (_windows) parts.first.substring(0, 1),
      ...parts.skip(1),
    ]);
  }

  String _posed(String real) {
    if (!p.isWithin(root, real)) return real;
    final parts = p.split(p.relative(real, from: root));
    return _windows
        ? p.windows.joinAll(['${parts.first}:\\', ...parts.skip(1)])
        : p.posix.joinAll(['/', ...parts]);
  }

  @override
  Future<ProcessOutput?> runProcess(String executable, List<String> args) {
    calls.add([executable, ...args]);
    return run?.call(executable, args) ?? Future.value();
  }

  @override
  bool exists(String path) => super.exists(real(path));

  @override
  bool isFile(String path) => super.isFile(real(path));

  @override
  bool isLink(String path) => super.isLink(real(path));

  @override
  bool isDirectory(String path) => super.isDirectory(real(path));

  @override
  List<String> listDirectories(String path) =>
      super.listDirectories(real(path)).map(_posed).toList();

  @override
  String? resolve(String path) {
    final r = super.resolve(real(path));
    return r == null ? null : _posed(r);
  }

  /// Makes a flavor folder [name] in [install] with an account, and a
  /// Memories file when [memories] is set.
  String flavor(String install, String name, {bool memories = false}) {
    final dir = pathContext.join(install, name);
    final sv = Directory(
      real(pathContext.join(dir, 'WTF', 'Account', 'ACC', 'SavedVariables')),
    )..createSync(recursive: true);
    if (memories) File(p.join(sv.path, 'Memories.lua')).writeAsStringSync('');
    return dir;
  }

  void mkdir(String path) => Directory(real(path)).createSync(recursive: true);
}

Runner registry(Map<String, String?> values, {int exitCode = 0}) =>
    (exe, args) async {
      final key = args[1];
      if (!values.containsKey(key)) return (exitCode: 1, stdout: '');
      final v = values[key];
      if (v == null) return null;
      return (
        exitCode: exitCode,
        stdout: '\r\n$key\r\n    InstallPath    REG_SZ    $v\r\n\r\n',
      );
    };

const wow64 =
    r'HKLM\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft';
const wow32 = r'HKLM\SOFTWARE\Blizzard Entertainment\World of Warcraft';
const pf86 = r'C:\Program Files (x86)\World of Warcraft';
const home = '/home/u';

List<(String, String, bool)> summary(List<WowFolder> folders) => [
  for (final f in folders) (f.installDir, f.flavor, f.hasMemoriesData),
];

void main() {
  late String tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('memories-disc-').path);
  tearDown(() {
    // The tests that lock a folder leave it locked; delete needs it open.
    if (!Platform.isWindows) Process.runSync('chmod', ['-R', 'u+rwx', tmp]);
    Directory(tmp).deleteSync(recursive: true);
  });

  FakeEnvironment windows({Runner? run}) => FakeEnvironment(
    tmp,
    'windows',
    env: const {'USERPROFILE': r'C:\Users\u'},
    run: run,
  );
  FakeEnvironment mac() =>
      FakeEnvironment(tmp, 'macos', env: const {'HOME': '/Users/u'});
  FakeEnvironment linux() =>
      FakeEnvironment(tmp, 'linux', env: const {'HOME': home});

  group('discoverWow on Windows', () {
    final cases =
        <
          (
            String,
            Map<String, String?>,
            void Function(FakeEnvironment),
            List<(String, String, bool)>,
          )
        >[
          (
            'found by the registry, value with a trailing slash',
            {wow64: r'D:\Games\WoW\_retail_\'},
            (e) => e.flavor(r'D:\Games\WoW', '_retail_', memories: true),
            [(r'D:\Games\WoW', '_retail_', true)],
          ),
          (
            'the registry value is a drive root',
            {wow32: r'E:\'},
            (e) => e.flavor(r'E:\', '_classic_'),
            [(r'E:\', '_classic_', false)],
          ),
          (
            'the registry command is missing',
            {wow64: null, wow32: null},
            (e) => e
              ..flavor(pf86, '_retail_')
              ..flavor(pf86, '_forever_'),
            [(pf86, '_forever_', false), (pf86, '_retail_', false)],
          ),
          (
            'the registry key is missing',
            {},
            (e) => e.flavor(r'C:\Games\World of Warcraft', '_retail_'),
            [(r'C:\Games\World of Warcraft', '_retail_', false)],
          ),
          ('not found', {}, (e) => e.mkdir(r'C:\Program Files'), []),
          (
            'the same folder from both keys and the fixed path',
            {wow64: '$pf86\\_retail_', wow32: '$pf86\\_retail_'},
            (e) => e.flavor(pf86, '_retail_', memories: true),
            [(pf86, '_retail_', true)],
          ),
          (
            'other fixed drives that exist',
            {},
            (e) => e
              ..flavor(r'F:\Program Files\World of Warcraft', '_retail_')
              ..flavor(r'D:\Games\World of Warcraft', '_forever_'),
            [
              (r'D:\Games\World of Warcraft', '_forever_', false),
              (r'F:\Program Files\World of Warcraft', '_retail_', false),
            ],
          ),
        ];
    for (final (name, values, build, want) in cases) {
      test(name, () async {
        final env = windows(run: registry(values));
        build(env);
        expect(summary(await discoverWow(environment: env)), want);
        expect(env.calls, [
          [r'C:\Windows\System32\reg.exe', 'query', wow64, '/v', 'InstallPath'],
          [r'C:\Windows\System32\reg.exe', 'query', wow32, '/v', 'InstallPath'],
        ]);
      });
    }

    test('reg.exe is run from SystemRoot', () async {
      final env = FakeEnvironment(
        tmp,
        'windows',
        env: const {'SystemRoot': r'D:\WINNT'},
      );
      await discoverWow(environment: env);
      expect(env.calls.map((c) => c.first).toSet(), {
        r'D:\WINNT\System32\reg.exe',
      });
    });

    test('an empty or relative SystemRoot is not used', () async {
      for (final root in ['', 'WINNT', r'\WINNT']) {
        final env = FakeEnvironment(tmp, 'windows', env: {'SystemRoot': root});
        await discoverWow(environment: env);
        expect(env.calls.map((c) => c.first).toSet(), {
          r'C:\Windows\System32\reg.exe',
        }, reason: root);
      }
    });

    test(
      'a registry value that is not a full path is not a candidate',
      () async {
        for (final value in [r'%NOPE%\WoW\_retail_', '_retail_', r'\WoW\_x_']) {
          final env = windows(run: registry({wow64: value}));
          final candidates = await installCandidates(env);
          expect(candidates.first, r'C:\Program Files (x86)\World of Warcraft');
          expect(
            candidates.where((c) => p.windows.rootPrefix(c).length < 3),
            isEmpty,
            reason: value,
          );
        }
      },
    );

    test('a REG_EXPAND_SZ value has its variables expanded', () async {
      final env = FakeEnvironment(
        tmp,
        'windows',
        env: const {'GAMES': r'D:\Games'},
        run: (exe, args) async => args[1] == wow64
            ? (
                exitCode: 0,
                stdout:
                    '    InstallPath    REG_EXPAND_SZ    '
                    '%GAMES%\\WoW\\_retail_\\\r\n',
              )
            : (
                exitCode: 0,
                stdout:
                    '    InstallPath    REG_EXPAND_SZ    '
                    '%NOPE%\\WoW\\_retail_\r\n',
              ),
      )..flavor(r'D:\Games\WoW', '_retail_');
      expect(summary(await discoverWow(environment: env)), [
        (r'D:\Games\WoW', '_retail_', false),
      ]);
    });

    test('a failing registry command is ignored', () async {
      final env = windows(run: registry({wow64: r'D:\X\_retail_'}, exitCode: 1))
        ..flavor(r'D:\X', '_retail_');
      expect(await discoverWow(environment: env), isEmpty);
    });

    test('the flavor path is reported with Windows rules', () async {
      final env = windows(run: registry({}))..flavor(pf86, '_retail_');
      final found = await discoverWow(environment: env);
      expect(found.single.flavorDir, '$pf86\\_retail_');
    });
  });

  group('discoverWow on macOS', () {
    test('two places, sorted by data then forever', () async {
      final env = mac();
      const apps = '/Applications/World of Warcraft';
      const mine = '/Users/u/Applications/World of Warcraft';
      env
        ..flavor(apps, '_anniversary_')
        ..flavor(apps, '_retail_', memories: true)
        ..flavor(mine, '_forever_', memories: true)
        ..flavor(mine, '_classic_forever_');
      expect(summary(await discoverWow(environment: env)), [
        (mine, '_forever_', true),
        (apps, '_retail_', true),
        (mine, '_classic_forever_', false),
        (apps, '_anniversary_', false),
      ]);
    });

    test('only folders named _x_ with WTF/Account count', () async {
      final env = mac();
      const apps = '/Applications/World of Warcraft';
      env
        ..flavor(apps, 'Data')
        ..flavor(apps, '_x')
        ..mkdir('$apps/_ptr_/WTF')
        ..mkdir('$apps/_beta_/WTF/Account/A/SavedVariables/Memories.lua');
      File(env.real('$apps/_file_')).writeAsStringSync('');
      expect(summary(await discoverWow(environment: env)), [
        (apps, '_beta_', false),
      ]);
    });

    test('not found', () async {
      expect(await discoverWow(environment: mac()), isEmpty);
    });
  });

  group('discoverWow on Linux', () {
    test('many Steam prefixes, Bottles, Wine and Lutris', () async {
      final env = linux();
      const steam = '$home/.local/share/Steam/steamapps/compatdata';
      const wowIn = 'drive_c/Program Files (x86)/World of Warcraft';
      const flatpakSteam =
          '$home/.var/app/com.valvesoftware.Steam/.local/share/Steam/'
          'steamapps/compatdata';
      for (var i = 0; i < 30; i++) {
        env.mkdir('$steam/$i/pfx/drive_c/windows');
      }
      env
        ..flavor('$steam/7/pfx/$wowIn', '_retail_', memories: true)
        ..flavor('$steam/2981/pfx/$wowIn', '_forever_')
        ..flavor(
          '$home/.var/app/com.usebottles.bottles/data/bottles/bottles/bnet/$wowIn',
          '_classic_',
        )
        ..flavor('$home/.local/share/bottles/bottles/bnet/$wowIn', '_anniv_')
        ..flavor('$home/.wine/$wowIn', '_classic_era_')
        ..flavor('$flatpakSteam/40/pfx/$wowIn', '_steam_')
        ..flavor('$home/Games/world-of-warcraft', '_retail_')
        ..flavor('$home/Games/battlenet/$wowIn', '_beta_')
        ..flavor('$home/Games/wow-lutris/$wowIn', '_ptr_');
      expect(summary(await discoverWow(environment: env)), [
        ('$steam/7/pfx/$wowIn', '_retail_', true),
        ('$steam/2981/pfx/$wowIn', '_forever_', false),
        ('$home/Games/world-of-warcraft', '_retail_', false),
        ('$home/Games/battlenet/$wowIn', '_beta_', false),
        ('$home/Games/wow-lutris/$wowIn', '_ptr_', false),
        ('$home/.wine/$wowIn', '_classic_era_', false),
        ('$flatpakSteam/40/pfx/$wowIn', '_steam_', false),
        (
          '$home/.var/app/com.usebottles.bottles/data/bottles/bottles/bnet/$wowIn',
          '_classic_',
          false,
        ),
        ('$home/.local/share/bottles/bottles/bnet/$wowIn', '_anniv_', false),
      ]);
    });

    test(
      'a WTF linked to a sibling flavor is refused, as when picked',
      () async {
        final env = linux();
        const install = '$home/Games/world-of-warcraft';
        env
          ..flavor(install, '_classic_')
          ..mkdir('$install/_retail_');
        Link(env.real('$install/_retail_/WTF'))
            .createSync(env.real('$install/_classic_/WTF'));
        expect(summary(await discoverWow(environment: env)), [
          (install, '_classic_', false),
        ]);
        expect(
          validateFlavorDir('$install/_retail_', environment: env),
          isA<NoWtf>(),
        );
      },
    );

    test(
      'an install folder with only _retail_ is listed with no data',
      () async {
        final env = linux()
          ..flavor('$home/Games/world-of-warcraft', '_retail_');
        final found = await discoverWow(environment: env);
        expect(found, [
          const WowFolder(
            installDir: '$home/Games/world-of-warcraft',
            flavorDir: '$home/Games/world-of-warcraft/_retail_',
            flavor: '_retail_',
            hasMemoriesData: false,
          ),
        ]);
        expect(found.single.toString(), contains('_retail_'));
        expect(
          found.single.hashCode,
          const WowFolder(
            installDir: '$home/Games/world-of-warcraft',
            flavorDir: '$home/Games/world-of-warcraft/_retail_',
            flavor: '_retail_',
            hasMemoriesData: false,
          ).hashCode,
        );
      },
    );

    test('links: broken, out of the candidate, and twice the same', () async {
      final env = linux();
      const install = '$home/Games/world-of-warcraft';
      final outside = Directory(p.join(tmp, 'outside'))..createSync();
      Directory(
        p.join(outside.path, '_away_', 'WTF', 'Account', 'A', 'SavedVariables'),
      ).createSync(recursive: true);
      env
        ..mkdir('$home/Games')
        ..flavor(install, '_retail_', memories: true)
        ..mkdir('$install/_wtflink_')
        ..mkdir('$home/x');
      Link(env.real('$home/.wine')).createSync(p.join(tmp, 'gone'));
      Link(env.real('$install/_away_'))
          .createSync(p.join(outside.path, '_away_'));
      Link(env.real('$install/_wtflink_/WTF'))
          .createSync(p.join(outside.path, '_away_', 'WTF'));
      Link(env.real('$install/_same_'))
          .createSync(env.real('$install/_retail_'));
      expect(summary(await discoverWow(environment: env)), [
        (install, '_retail_', true),
      ]);
    });

    test('a Memories file reached by a link out is not data', () async {
      final env = linux();
      const install = '$home/Games/world-of-warcraft';
      final dir = env.flavor(install, '_retail_');
      final sv = env.real('$dir/WTF/Account/ACC/SavedVariables');
      final outside = File(p.join(tmp, 'Memories.lua'))..writeAsStringSync('');
      Link(p.join(sv, 'Memories.lua')).createSync(outside.path);
      expect(summary(await discoverWow(environment: env)), [
        (install, '_retail_', false),
      ]);
    });

    test('a Memories file linked inside the folder is not data', () async {
      final env = linux();
      const install = '$home/Games/world-of-warcraft';
      final dir = env.flavor(install, '_retail_');
      final sv = env.real('$dir/WTF/Account/ACC/SavedVariables');
      final inside = File(p.join(sv, 'Other.lua'))..writeAsStringSync('');
      Link(p.join(sv, 'Memories.lua')).createSync(inside.path);
      expect(summary(await discoverWow(environment: env)), [
        (install, '_retail_', false),
      ]);
    });

    test('a linked account inside the folder is not data', () async {
      final env = linux();
      const install = '$home/Games/world-of-warcraft';
      final dir = env.flavor(install, '_retail_');
      final accounts = env.real('$dir/WTF/Account');
      final realSv = Directory(p.join(accounts, 'ACC', 'X', 'SavedVariables'))
        ..createSync(recursive: true);
      File(p.join(realSv.path, 'Memories.lua')).writeAsStringSync('');
      Link(p.join(accounts, 'LINKED')).createSync(p.join(accounts, 'ACC', 'X'));
      expect(summary(await discoverWow(environment: env)), [
        (install, '_retail_', false),
      ]);
    });

    test('a folder that cannot be read is left out', () async {
      final env = linux()
        ..flavor('$home/Games/world-of-warcraft', '_retail_')
        ..flavor(
          '$home/.wine/drive_c/Program Files (x86)/World of Warcraft',
          '_a_',
        )
        ..mkdir('$home/.local/share/Steam/steamapps/compatdata');
      Process.runSync('chmod', [
        '000',
        env.real('$home/Games/world-of-warcraft'),
      ]);
      Process.runSync('chmod', [
        '000',
        env.real(
          '$home/.wine/drive_c/Program Files (x86)/World of Warcraft/_a_/WTF/Account',
        ),
      ]);
      Process.runSync('chmod', [
        '000',
        env.real('$home/.local/share/Steam/steamapps/compatdata'),
      ]);
      expect(await discoverWow(environment: env), isEmpty);
    }, testOn: 'linux || mac-os');

    test('no home and other systems find nothing', () async {
      expect(
        await discoverWow(environment: FakeEnvironment(tmp, 'linux')),
        isEmpty,
      );
      expect(
        await discoverWow(environment: FakeEnvironment(tmp, 'fuchsia')),
        isEmpty,
      );
    });
  });

  group('validateFlavorDir', () {
    const install = '$home/Games/world-of-warcraft';

    test('the picked folder is the flavor folder', () {
      final env = linux()..flavor(install, '_retail_', memories: true);
      final check = validateFlavorDir('$install/_retail_/', environment: env);
      expect(check, isA<Valid>());
      final valid = check as Valid;
      expect(valid.flavorDir, '$install/_retail_');
      expect(valid.folder.installDir, install);
      expect(valid.folder.hasMemoriesData, isTrue);
      expect(valid.message, 'This WoW folder is ready.');
    });

    test('the picked folder is the install folder', () {
      final env = linux()
        ..flavor(install, '_retail_')
        ..flavor(install, '_forever_', memories: true);
      final check = validateFlavorDir(install, environment: env);
      expect(check, isA<IsInstallFolder>());
      final flavors = (check as IsInstallFolder).flavors;
      expect(flavors.map((f) => f.flavor), ['_forever_', '_retail_']);
      expect(check.path, install);
      expect(check.message, contains('2 game versions: _forever_, _retail_'));
    });

    test('an install folder lists a linked flavor once', () {
      final env = linux()..flavor(install, '_retail_');
      Link(env.real('$install/_same_'))
          .createSync(env.real('$install/_retail_'));
      final check = validateFlavorDir(install, environment: env);
      expect((check as IsInstallFolder).flavors.map((f) => f.flavor), [
        '_retail_',
      ]);
    });

    test('an install folder with one flavor names it', () {
      final env = linux()..flavor(install, '_retail_');
      final check = validateFlavorDir(install, environment: env);
      expect(check.message, contains('one game version: _retail_. Pick that'));
    });

    test('no WTF/Account', () {
      final env = linux()..mkdir('$install/_retail_/WTF');
      for (final path in [install, '$install/_retail_']) {
        final check = validateFlavorDir(path, environment: env);
        expect(check, isA<NoWtf>());
        expect((check as NoWtf).path, path);
        expect(check.message, contains('no WTF/Account folder'));
      }
    });

    test('a WTF folder linked out of the picked folder does not count', () {
      final env = linux()..mkdir(install);
      final away = Directory(p.join(tmp, 'away', 'WTF', 'Account'))
        ..createSync(recursive: true);
      Link(env.real('$install/WTF')).createSync(p.dirname(away.path));
      expect(validateFlavorDir(install, environment: env), isA<NoWtf>());
    });

    test('a file, a missing path and a broken link are not folders', () {
      final env = linux()..mkdir(home);
      File(env.real('$home/file')).writeAsStringSync('');
      Link(env.real('$home/broken')).createSync(p.join(tmp, 'gone'));
      for (final path in ['$home/file', '$home/none', '$home/broken']) {
        final check = validateFlavorDir(path, environment: env);
        expect(check, isA<NotADirectory>(), reason: path);
        expect((check as NotADirectory).path, path);
        expect(check.message, contains('Pick a folder.'));
      }
    });

    test('a folder or an account folder that cannot be read', () {
      final env = linux()
        ..flavor(install, '_retail_')
        ..mkdir('$home/locked');
      Process.runSync('chmod', ['000', env.real('$home/locked')]);
      Process.runSync('chmod', [
        '000',
        env.real('$install/_retail_/WTF/Account'),
      ]);
      for (final path in ['$home/locked', '$install/_retail_']) {
        final check = validateFlavorDir(path, environment: env);
        expect(check, isA<NotReadable>(), reason: path);
        expect((check as NotReadable).path, path);
        expect(check.message, contains('cannot be read'));
      }
    }, testOn: 'linux || mac-os');

    test('a flavor with no Memories data tells how to make it', () {
      final env = windows()..flavor(pf86, '_retail_');
      final check = validateFlavorDir('$pf86\\_retail_', environment: env);
      expect(check, isA<Valid>());
      expect((check as Valid).folder.installDir, pf86);
      expect(check.message, contains('no Memories data yet'));
      expect(check.message, contains('/reload'));
    });

    test('the fixture is a valid folder with Memories data', () {
      final check = validateFlavorDir(fixtureWow);
      expect(check, isA<Valid>());
      final folder = (check as Valid).folder;
      expect(folder.flavor, 'wow');
      expect(folder.hasMemoriesData, isTrue);
      expect(folder.flavorDir, p.normalize(p.absolute(fixtureWow)));
      expect(folder.installDir, p.dirname(folder.flavorDir));
    });
  });

  group('the default environment', () {
    const env = Environment();

    test('reads this system', () {
      expect(env.operatingSystem, Platform.operatingSystem);
      expect(env.env, Platform.environment);
      expect(env.pathContext.current, p.current);
    });

    test('runs a command, and a missing one gives null', () async {
      expect(await env.runProcess('memories-no-such-command', []), isNull);
      final r = await env.runProcess(Platform.resolvedExecutable, [
        '--version',
      ]);
      expect(r?.exitCode, 0);
    });

    test('output that cannot be decoded gives null', () async {
      expect(await env.runProcess('sh', ['-c', r"printf '\377'"]), isNull);
    }, testOn: 'linux || mac-os');

    test('a home that is empty is none', () {
      expect(
        FakeEnvironment(tmp, 'linux', env: const {'HOME': ''}).home,
        isNull,
      );
      expect(windows().home, r'C:\Users\u');
    });
  });

  group('bin/discover.dart', () {
    Future<ProcessResult> discover(List<String> args) => Process.run(
      Platform.resolvedExecutable,
      ['bin/discover.dart', ...args],
      // A fake home keeps the run away from a real install.
      environment: {'HOME': tmp},
    );

    test('finds nothing in an empty home', () async {
      final r = await discover([]);
      expect(r.stdout, 'No WoW folder found. Pick it by hand.\n');
      expect(r.exitCode, 1);
    }, testOn: 'linux');

    test('lists the folders in a home', () async {
      final env = linux();
      env.flavor('/Games/world-of-warcraft', '_retail_', memories: true);
      final r = await discover([]);
      expect(
        r.stdout,
        '${p.join(tmp, 'Games', 'world-of-warcraft', '_retail_')} '
        '(flavor _retail_, Memories data: yes)\n',
      );
      expect(r.exitCode, 0);
    }, testOn: 'linux');

    test('checks a picked folder', () async {
      final ok = await discover([fixtureWow]);
      expect(ok.stdout, startsWith('This WoW folder is ready.\n'));
      expect(ok.stdout, contains('(flavor wow, Memories data: yes)'));
      expect(ok.exitCode, 0);

      final env = linux()..flavor('/i', '_retail_');
      final install = await discover([env.real('/i')]);
      expect(install.stdout, contains('This is the World of Warcraft folder.'));
      expect(install.stdout, contains('(flavor _retail_, Memories data: no)'));
      expect(install.exitCode, 1);

      final bad = await discover([p.join(tmp, 'none')]);
      expect(bad.stdout, contains('This is not a folder'));
      expect(bad.exitCode, 1);

      final usage = await discover(['a', 'b']);
      expect(usage.stderr, 'usage: discover [folder]\n');
      expect(usage.exitCode, 2);
    });
  });
}
