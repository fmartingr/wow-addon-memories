import 'dart:io';

import 'package:memories_core/src/gather/cli.dart';
import 'package:memories_core/src/gather/files.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/fixture.dart';

Future<({int code, String out, String err})> execute(List<String> args) async {
  final out = StringBuffer();
  final err = StringBuffer();
  final code = await runMemoriesExport(
    args,
    out: out,
    err: err,
    now: () => DateTime.utc(2026, 11, 7, 12),
  );
  return (code: code, out: out.toString(), err: err.toString());
}

void main() {
  late String tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('memories-cli-').path);
  tearDown(() => Directory(tmp).deleteSync(recursive: true));

  test('usage errors and exit codes', () async {
    final cases = [
      ('no arguments', <String>[], 2, 'usage:'),
      ('help', ['-h'], 0, '-wow-dir'),
      ('unknown flag', ['--nope'], 2, 'flag provided but not defined: -nope'),
      ('missing value', ['--wow-dir'], 2, 'flag needs an argument: -wow-dir'),
      ('extra argument', ['--wow-dir', fixtureWow, 'x'], 2, 'usage:'),
      ('empty dist', ['--wow-dir', fixtureWow, '--dist', ''], 2, 'usage:'),
      (
        'unknown default',
        [
          '--wow-dir',
          fixtureWow,
          '--dist',
          p.join(tmp, 'd'),
          '--backup',
          p.join(tmp, 'b'),
          '--default',
          'eu-x-y',
        ],
        2,
        'is not a character id',
      ),
      (
        'dist in WTF',
        ['--wow-dir', fixtureWow, '--dist', p.join(fixtureWow, 'WTF', 'out')],
        2,
        'never writes',
      ),
      (
        'backup in Screenshots',
        [
          '--wow-dir',
          fixtureWow,
          '--dist',
          p.join(tmp, 'd'),
          '--backup',
          p.join(fixtureWow, 'Screenshots'),
        ],
        2,
        'never writes',
      ),
      (
        'not a flavor folder',
        [
          '--wow-dir',
          tmp,
          '--dist',
          p.join(tmp, 'd'),
          '--backup',
          p.join(tmp, 'b'),
        ],
        1,
        'no WTF/Account folder',
      ),
    ];
    for (final (name, args, code, msg) in cases) {
      final r = await execute(args);
      expect(r.code, code, reason: '$name: ${r.err}');
      expect(r.err, contains(msg), reason: name);
    }
    expect(Directory(p.join(fixtureWow, 'WTF', 'out')).existsSync(), isFalse);
    expect(
      (await execute([])).err,
      'usage: memories-export --wow-dir <flavor dir> [--dist DIR] '
      '[--backup DIR] [--default ID]\n',
    );
  });

  test('accepts the Go form of the flags', () async {
    final dist = p.join(tmp, '-d');
    final r = await execute([
      '-wow-dir',
      fixtureWow,
      '-dist',
      dist,
      '-backup=${p.join(tmp, 'b')}',
    ]);
    expect(r.code, 0, reason: r.err);
    expect(r.out, contains('wrote 2 characters to $dist'));
    expect((await execute(['-help'])).code, 0);
    expect((await execute(['-x'])).code, 2);
  });

  test('a run that another gather blocks gives exit 1', () async {
    final first = GatherLock.acquire(tmp)!;
    addTearDown(first.release);
    final r = await execute([
      '--wow-dir',
      fixtureWow,
      '--dist',
      p.join(tmp, 'd'),
      '--backup',
      p.join(tmp, 'b'),
    ]);
    expect(r.code, 1);
    expect(r.err, contains('another gather is running'));
  });

  test('a failed character gives exit 1 after the run', () async {
    final dist = p.join(tmp, 'd');
    Directory(p.join(dist, 'eu-brumamar-nandu')).createSync(recursive: true);
    File(p.join(dist, 'eu-brumamar-nandu', 'journey.jsonl'))
        .writeAsStringSync('{broken\n');
    final r = await execute([
      '--wow-dir',
      fixtureWow,
      '--dist',
      dist,
      '--backup',
      p.join(tmp, 'b'),
    ]);
    expect(r.code, 1);
    expect(r.err, 'memories-export: 1 characters and 0 accounts failed\n');
    expect(r.out, contains('wrote 1 characters'));
  });

  test('dart run on the fixture writes the golden files', () async {
    final dist = p.join(tmp, 'dist');
    final r = await Process.run(Platform.resolvedExecutable, [
      'run',
      'bin/memories_export.dart',
      '--wow-dir',
      fixtureWow,
      '--dist',
      dist,
      '--backup',
      p.join(tmp, 'backups'),
    ]);
    expect(r.exitCode, 0, reason: '${r.stderr}');
    expect(r.stdout, contains('copied 2 screenshots, 1 not found; backup in '));
    expect(r.stdout, contains('wrote 2 characters to $dist'));
    expect(readTree(dist), readTree(expectedDir));

    final usage = await Process.run(Platform.resolvedExecutable, [
      'run',
      'bin/memories_export.dart',
    ]);
    expect(usage.exitCode, 2);
    expect(
      usage.stderr,
      contains(
        'usage: memories-export --wow-dir <flavor dir> [--dist DIR] '
        '[--backup DIR] [--default ID]',
      ),
    );
  });
}
