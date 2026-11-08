import 'dart:io';

import 'package:memories_core/memories_core.dart';
import 'package:memories_core/src/gather/files.dart';
import 'package:memories_core/src/gather/gather.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fixture.dart';

const mainId = 'eu-brumamar-nandu';
const otherId = 'eu-los-errantes-nandu';

final DateTime fixedNow = DateTime.utc(2026, 11, 7, 12);

Future<({String out, GatherResult result})> runOn(
  String wow,
  String dist, {
  String def = '',
  String? backup,
}) async {
  final out = StringBuffer();
  final result = await gather(
    GatherOptions(
      wowDir: Directory(wow),
      dist: Directory(dist),
      backup: Directory(backup ?? p.join(p.dirname(dist), 'backups')),
      defaultId: def,
      now: fixedNow,
      onEvent: (e) => out.writeln(e.line),
    ),
  );
  return (out: out.toString(), result: result);
}

List<JournalRecord> journey(String dist, String id) => readJsonl(
  p.join(dist, id, 'journey.jsonl'),
  (row) => JournalRecord(row! as Map<String, Object?>),
);

String? indexDefault(String dist) =>
    readJson(p.join(dist, 'index.json'))?['default_character'] as String?;

List<String> glob(String root, List<String> parts) {
  var paths = [root];
  for (final part in parts) {
    final next = <String>[];
    for (final dir in paths) {
      if (part != '*') {
        next.add(p.join(dir, part));
        continue;
      }
      if (!Directory(dir).existsSync()) continue;
      next.addAll(Directory(dir).listSync().map((e) => e.path));
    }
    paths = next;
  }
  return paths.where((x) => File(x).existsSync()).toList();
}

String account(String wow) => p.join(wow, 'WTF', 'Account', 'TESTACCOUNT');

void main() {
  late ({String root, String wow, String dist, String backup}) fx;

  setUp(() => fx = copyFixture());
  tearDown(() => Directory(fx.root).deleteSync(recursive: true));

  group('fixture', () {
    test('writes the golden files, the log lines and the backups', () async {
      final before = readTree(fixtureWow);
      final r = await runOn(fixtureWow, fx.dist);
      expect(r.result.error, isNull, reason: r.out);
      for (final want in [
        'Memories_Social.lua: line 4, column 1',
        'eu-brumamar-nandu: 15 records, 3 trail points, 1 sessions, '
            '2 screenshots, addons Memories, Memories_Combat, Memories_Gathering',
        'skipped 1 lines',
        'joined 2 notes',
        'copied 2 screenshots, 1 not found',
      ]) {
        expect(r.out, contains(want));
      }
      expect(r.result.characters, 2);
      expect(r.result.lines, 16);
      expect(r.result.screenshots, 2);
      expect(r.result.files, 6);
      expect(r.result.damaged, 1);
      expect(r.result.issues.map((i) => i.code), [GatherIssueCode.damagedFile]);

      final got = readTree(fx.dist);
      expect(got, readTree(expectedDir));

      final backups = glob(fx.backup, [
        '*',
        'savedvariables',
        'wow',
        'TESTACCOUNT',
        '*',
        '*',
        'SavedVariables',
        '*',
      ]).where((x) => x.endsWith('.lua'));
      expect(backups, hasLength(5));
      final stamp = Directory(fx.backup).listSync().single.path;
      expect(p.basename(stamp), '20261107T120000Z');
      final shots = glob(fx.backup, [
        '*',
        'screenshots',
        '*',
      ]).where((x) => x.endsWith('.jpg'));
      expect(shots, hasLength(2));

      final again = await runOn(fixtureWow, fx.dist);
      expect(again.result.error, isNull);
      expect(readTree(fx.dist), got, reason: 'a second run changed the output');
      expect(readTree(fixtureWow), before, reason: 'the input changed');
    });

    test('keeps the screenshot times of the source', () async {
      await runOn(fx.wow, fx.dist);
      const name = 'WoWScrnShot_110126_114820.jpg';
      expect(
        File(p.join(fx.dist, mainId, 'screenshots', name)).lastModifiedSync(),
        File(p.join(fx.wow, 'Screenshots', name)).lastModifiedSync(),
      );
    });

    test('ignores a stale temporary file in the output', () async {
      Directory(p.join(fx.dist, mainId)).createSync(recursive: true);
      File(p.join(fx.dist, '.memories-1.tmp')).writeAsStringSync('half');
      File(p.join(fx.dist, mainId, '.memories-2.tmp')).writeAsStringSync('x');
      final r = await runOn(fx.wow, fx.dist);
      expect(r.result.error, isNull);
      final got = readTree(fx.dist)
        ..remove('.memories-1.tmp')
        ..remove('$mainId/.memories-2.tmp');
      final want = readTree(expectedDir);
      expect(got.keys, unorderedEquals(want.keys));
      expect(got['$mainId/journey.jsonl'], want['$mainId/journey.jsonl']);
    });
  });

  group('reinstall', () {
    test('keeps the earlier records and adds the new one once', () async {
      expect((await runOn(fx.wow, fx.dist)).result.error, isNull);
      final sv = p.join(account(fx.wow), 'Brumamar', 'Ñandú', 'SavedVariables');
      for (final f in Directory(sv).listSync()) {
        f.deleteSync();
      }
      File(p.join(sv, 'Memories.lua')).writeAsStringSync('''
MemoriesCharDB = {
	["char"] = {
		["class"] = "HUNTER",
		["guid"] = "Player-1234-0ABCDEF0",
		["level"] = 11,
		["name"] = "Ñandú",
		["realm"] = "Brumamar",
	},
	["log"] = {
		["open"] = {
			"1793600050|6000|1429|4700|5900|lv|11",
		},
	},
	["schema"] = 1,
	["sessions"] = {
		{
			["computer"] = "a1b2c3",
			["last"] = 1793600100,
			["start"] = 1793600000,
			["tz"] = 3600,
		},
	},
}
''');
      for (var run = 0; run < 2; run++) {
        final r = await runOn(fx.wow, fx.dist);
        expect(r.result.error, isNull, reason: r.out);
        final rows = journey(fx.dist, mainId);
        expect(rows, hasLength(16));
        final added = rows.where((x) => x.time == 1793600050).toList();
        expect(added, hasLength(1));
        expect(added.single['level'], 11);
        expect(added.single['session'], 2);
        expect(
          rows.where((x) => x.text('screenshot').isNotEmpty),
          hasLength(2),
        );
        final char = readJson(p.join(fx.dist, mainId, 'character.json'))!;
        expect(char['sessions'], hasLength(2));
        expect(char['level'], 11);
        final index = readJson(p.join(fx.dist, 'index.json'))!;
        expect(index['characters'], hasLength(2));
      }
    });
  });

  group('earlier runs', () {
    test('keeps the records and the default of earlier runs', () async {
      expect((await runOn(fx.wow, fx.dist)).result.error, isNull);
      expect(indexDefault(fx.dist), mainId);
      File(p.join(fx.dist, mainId, 'journey.jsonl')).writeAsStringSync(
        '{"addon":"Memories","k":"lv","level":2,"t":1793529000}\n',
        mode: FileMode.append,
      );
      File(p.join(fx.wow, 'Screenshots', 'WoWScrnShot_110126_115001.jpg'))
          .deleteSync();

      expect((await runOn(fx.wow, fx.dist, def: otherId)).result.error, isNull);
      final rows = journey(fx.dist, mainId);
      expect(rows, hasLength(16));
      expect(rows.first.text('k'), 'lv');
      expect(rows.first['session'], isNull);
      expect(
        rows.where((r) => r.text('screenshot').isNotEmpty),
        hasLength(2),
        reason: 'a screenshot gone from the Screenshots folder lost its link',
      );

      expect((await runOn(fx.wow, fx.dist)).result.error, isNull);
      expect(indexDefault(fx.dist), otherId);
    });

    test('leaves a character with damaged earlier output as it was', () async {
      Directory(p.join(fx.dist, mainId)).createSync(recursive: true);
      final journeyFile = File(p.join(fx.dist, mainId, 'journey.jsonl'))
        ..writeAsStringSync('{broken\n');
      final r = await runOn(fx.wow, fx.dist, def: mainId);
      expect(r.result.error, '1 characters and 0 accounts failed');
      expect(r.out, contains('left as it was'));
      expect(
        r.result.issues.map((i) => i.code),
        contains(GatherIssueCode.characterFailed),
      );
      expect(indexDefault(fx.dist), otherId);
      expect(r.out, contains('has no entry in index.json'));
      expect(
        r.result.issues.where((i) => i.code == GatherIssueCode.badDefault),
        hasLength(1),
      );
      expect(r.result.stop, isNull);
      expect(journeyFile.readAsStringSync(), '{broken\n');
      expect(journey(fx.dist, otherId), hasLength(1));
      for (final name in ['trail.jsonl', 'character.json']) {
        journeyFile.writeAsStringSync('');
        final f = File(p.join(fx.dist, mainId, name))
          ..writeAsStringSync('{broken\n');
        expect(
          (await runOn(fx.wow, fx.dist)).result.error,
          isNotNull,
          reason: 'a damaged $name was read',
        );
        f.deleteSync();
      }
    });

    test('refuses a journal row that is not an object', () async {
      Directory(p.join(fx.dist, mainId)).createSync(recursive: true);
      File(p.join(fx.dist, mainId, 'journey.jsonl')).writeAsStringSync('[1]\n');
      final r = await runOn(fx.wow, fx.dist);
      expect(r.out, contains('journey.jsonl line 1: a journal row'));
    });

    test('keeps ids and entries of earlier runs', () async {
      expect((await runOn(fx.wow, fx.dist)).result.error, isNull);
      Directory(p.join(account(fx.wow), 'Los Errantes'))
          .deleteSync(recursive: true);
      expect((await runOn(fx.wow, fx.dist)).result.error, isNull);
      final list = readJson(p.join(fx.dist, 'index.json'))!['characters'];
      expect(
        list,
        hasLength(2),
        reason: 'a character without saved files left the index',
      );

      File(p.join(fx.dist, otherId, 'character.json'))
          .writeAsStringSync('{"guid":"Player-1234-0ABCDEF0"}');
      File(p.join(fx.dist, 'index.json')).writeAsStringSync(
        '{"characters":[{"id":"$otherId","guid":"Player-1234-0ABCDEF0"}]}',
      );
      expect((await runOn(fx.wow, fx.dist)).result.error, isNull);
      expect(
        journey(fx.dist, mainId),
        isNotEmpty,
        reason: 'an earlier id that the name and realm cannot give was kept',
      );
      File(p.join(fx.dist, mainId, 'character.json'))
          .writeAsStringSync('{"guid":"Player-5678-0FEDCBA0"}');
      final r = await runOn(fx.wow, fx.dist);
      expect(r.result.error, isNotNull);
      expect(r.out, contains('holds the character with GUID'));
    });

    test('writes a kept earlier entry with sorted keys', () async {
      Directory(fx.dist).createSync(recursive: true);
      File(p.join(fx.dist, 'index.json')).writeAsStringSync(
        '{"characters":[{"id":"eu-old-one","guid":"Player-1","zeta":1,'
        '"alpha":"x"}]}',
      );
      expect((await runOn(fx.wow, fx.dist)).result.error, isNull);
      final text = File(p.join(fx.dist, 'index.json')).readAsStringSync();
      expect(
        text,
        contains(
          '  {\n   "alpha": "x",\n   "guid": "Player-1",\n   "id": '
          '"eu-old-one",\n   "zeta": 1\n  }\n ],',
        ),
      );
    });

    test('keeps the folder of a renamed character', () async {
      expect((await runOn(fx.wow, fx.dist)).result.error, isNull);
      const gone = '{"guid":"Player-9-0000000A"}';
      File(p.join(fx.dist, mainId, 'character.json')).writeAsStringSync(gone);
      File(p.join(fx.dist, 'index.json'))
          .writeAsStringSync('{"characters":[]}');
      final r = await runOn(fx.wow, fx.dist);
      expect(r.result.error, isNull, reason: r.out);
      expect(journey(fx.dist, '$mainId-forever'), isNotEmpty);
      expect(
        File(p.join(fx.dist, mainId, 'character.json')).readAsStringSync(),
        gone,
      );
    });

    test('stops on an index that cannot be read', () async {
      Directory(fx.dist).createSync(recursive: true);
      File(p.join(fx.dist, 'index.json')).writeAsStringSync('{broken');
      final r = await runOn(fx.wow, fx.dist);
      expect(r.result.error, contains('fix or remove it'));
      expect(r.result.stop!.code, GatherIssueCode.badIndex);
      expect(File(p.join(fx.dist, 'index.json')).readAsStringSync(), '{broken');
      expect(
        Directory(fx.backup).existsSync(),
        isFalse,
        reason: 'a refused run wrote backups',
      );
    });

    test('stops on an index that is not an object', () async {
      Directory(fx.dist).createSync(recursive: true);
      File(p.join(fx.dist, 'index.json')).writeAsStringSync('[1]');
      final r = await runOn(fx.wow, fx.dist);
      expect(r.result.stop!.code, GatherIssueCode.badIndex);
    });
  });

  group('saved files', () {
    test('handles the edge folders of an account', () async {
      final acc = account(fx.wow);
      File(p.join(fx.wow, 'WTF', 'Config.wtf')).deleteSync();
      final noKinds = p.join(fx.wow, 'WTF', 'Account', 'NOKINDS');
      final nandu = p.join(acc, 'Brumamar', 'Ñandú');
      copyTree(nandu, p.join(noKinds, 'Brumamar', 'Otra'));
      copyTree(nandu, p.join(noKinds, 'Zeta', 'Otra'));
      Directory(
        p.join(
          fx.wow,
          'WTF',
          'Account',
          'NODATA',
          'Brumamar',
          'Nadie',
          'SavedVariables',
        ),
      ).createSync(recursive: true);
      copyTree(nandu, p.join(acc, 'Otro', 'Ñandú'));
      final noGuid = p.join(acc, 'Brumamar', 'Singuid', 'SavedVariables');
      Directory(noGuid).createSync(recursive: true);
      File(p.join(noGuid, 'Memories.lua'))
          .writeAsStringSync('MemoriesCharDB = { ["char"] = {} }\n');
      File(p.join(noGuid, 'Memories_Combat.lua'))
          .writeAsStringSync('Other = {}\n');
      Directory(p.join(acc, 'Brumamar', 'Empty', 'SavedVariables'))
          .createSync(recursive: true);
      File(p.join(nandu, 'SavedVariables', 'Memories_Combat.lua'))
          .writeAsStringSync('Other = {}\n');

      final r = await runOn(fx.wow, fx.dist);
      expect(r.result.error, '0 characters and 1 accounts failed');
      for (final want in [
        'Singuid-Brumamar: no character GUID',
        'has the GUID of',
        'has no MemoriesCombatCharDB table',
        'account NOKINDS has character data but no Memories.lua',
      ]) {
        expect(r.out, contains(want));
      }
      expect(
        r.result.issues.map((i) => i.code),
        containsAll([
          GatherIssueCode.accountSkipped,
          GatherIssueCode.duplicateGuid,
          GatherIssueCode.skippedFile,
        ]),
      );
      // The copy in "Otro" has the GUID of the one in "Brumamar" and the same
      // last session; the one scanned later is kept. It was copied before the
      // Combat file of "Brumamar" lost its table, so it keeps its own.
      final rows = journey(fx.dist, 'xx-otro-nandu');
      expect(rows.map((r) => r.text('addon')), contains('Memories_Combat'));
      expect(journey(fx.dist, 'xx-brumamar-nandu'), isEmpty);
      for (final rec in rows) {
        if (rec.text('k') == 'ss') {
          expect(rec['why'], isNotNull, reason: 'the account kinds were used');
        }
      }
    });

    test('two characters with one GUID keep the one played last', () async {
      final acc = account(fx.wow);
      final nandu = p.join(acc, 'Brumamar', 'Ñandú');
      for (final realm in ['Aaa', 'Zzz']) {
        final copy = p.join(acc, realm, 'Ñandú');
        copyTree(nandu, copy);
        final f = File(p.join(copy, 'SavedVariables', 'Memories.lua'));
        f.writeAsStringSync(
          f.readAsStringSync().replaceAll(
            '["last"] = 1793530600',
            '["last"] = 1793530500',
          ),
        );
      }
      final r = await runOn(fx.wow, fx.dist);
      expect(r.result.error, isNull, reason: r.out);
      expect('has the GUID of'.allMatches(r.out), hasLength(2));
      final index = readJson(p.join(fx.dist, 'index.json'))!;
      expect(
        [
          for (final e in index['characters']! as List<Object?>)
            (e! as Map)['id'],
        ],
        [mainId, otherId],
      );
    });

    test('a damaged account file skips its characters', () async {
      expect((await runOn(fx.wow, fx.dist)).result.error, isNull);
      final before = File(p.join(fx.dist, mainId, 'journey.jsonl'))
          .readAsBytesSync();
      File(p.join(account(fx.wow), 'SavedVariables', 'Memories.lua'))
          .writeAsStringSync('MemoriesDB = {\n');
      final r = await runOn(fx.wow, fx.dist);
      expect(r.result.error, isNotNull);
      expect(
        File(p.join(fx.dist, mainId, 'journey.jsonl')).readAsBytesSync(),
        before,
      );
    });

    test('an account file without kinds skips its characters', () async {
      expect((await runOn(fx.wow, fx.dist)).result.error, isNull);
      final before = File(p.join(fx.dist, mainId, 'journey.jsonl'))
          .readAsBytesSync();
      File(p.join(account(fx.wow), 'SavedVariables', 'Memories.lua'))
          .writeAsStringSync('MemoriesDB = {\n}\n');
      final r = await runOn(fx.wow, fx.dist);
      expect(r.result.error, isNotNull);
      expect(r.out, contains('has no kinds'));
      expect(
        File(p.join(fx.dist, mainId, 'journey.jsonl')).readAsBytesSync(),
        before,
      );
    });

    test('an account without the file and without data is fine', () async {
      Directory(p.join(fx.wow, 'WTF', 'Account', 'EMPTY', 'SavedVariables'))
          .createSync(recursive: true);
      final r = await runOn(fx.wow, fx.dist);
      expect(r.result.error, isNull);
      final got = readTree(fx.dist);
      final want = readTree(expectedDir);
      for (final f in ['journey.jsonl', 'trail.jsonl']) {
        expect(got['$mainId/$f'], want['$mainId/$f']);
        expect(got['$otherId/$f'], want['$otherId/$f']);
      }
    });

    test('a sub-addon file of another character is skipped', () async {
      final sv = p.join(account(fx.wow), 'Brumamar', 'Ñandú', 'SavedVariables');
      File(p.join(sv, 'Memories_Pets.lua')).writeAsStringSync(
        'MemoriesPetsCharDB = { ["char"] = { ["guid"] = "Player-2" } }\n',
      );
      final r = await runOn(fx.wow, fx.dist);
      expect(r.out, contains('belongs to the character with GUID Player-2'));
      expect(r.result.error, isNull);
      expect(
        r.result.issues.where((i) => i.code == GatherIssueCode.skippedFile),
        hasLength(1),
      );
    });

    test('a damaged sub-addon file leaves the output as it was', () async {
      expect((await runOn(fx.wow, fx.dist)).result.error, isNull);
      final before = readTree(fx.dist);
      final sv = p.join(account(fx.wow), 'Brumamar', 'Ñandú', 'SavedVariables');
      File(p.join(sv, 'Memories_Gathering.lua'))
          .writeAsStringSync('MemoriesGatheringCharDB = {\n');
      final r = await runOn(fx.wow, fx.dist);
      // The fixture's Memories_Social.lua is damaged too.
      expect(r.result.damaged, 2);
      expect(
        r.result.issues.map((i) => i.code),
        everyElement(GatherIssueCode.damagedFile),
      );
      expect(
        r.out,
        contains('addons Memories, Memories_Combat, Memories_Gathering'),
      );
      expect(readTree(fx.dist), before);
    });

    test('a saved file that cannot be read is reported', () async {
      final sv = p.join(account(fx.wow), 'Brumamar', 'Ñandú', 'SavedVariables');
      final f = File(p.join(sv, 'Memories_Gathering.lua'));
      Process.runSync('chmod', ['000', f.path]);
      addTearDown(() => Process.runSync('chmod', ['644', f.path]));
      final r = await runOn(fx.wow, fx.dist);
      expect(r.result.damaged, 2);
      expect(r.out, contains('warning: ${f.path}: '));
    }, testOn: 'linux || mac-os');

    test('reads the Forever folder layout', () async {
      final acc = account(fx.wow);
      Directory(p.join(acc, '93')).createSync();
      Directory(p.join(acc, 'Brumamar', 'Ñandú'))
          .renameSync(p.join(acc, '93', 'Ñandú-Brumamar'));
      Directory(p.join(acc, 'Brumamar')).deleteSync();
      expect((await runOn(fx.wow, fx.dist)).result.error, isNull);
      expect(journey(fx.dist, mainId), isNotEmpty);
    });

    test('reports a flavor folder with no character', () async {
      final wow = p.join(fx.root, 'wow');
      Directory(p.join(wow, 'WTF', 'Account', 'A', 'SavedVariables'))
          .createSync(recursive: true);
      final r = await runOn(wow, p.join(fx.root, 'out'));
      expect(r.result.error, contains('no character with Memories data'));
      expect(r.result.stop!.code, GatherIssueCode.noData);
    });

    test('refuses a default that names no character', () async {
      final r = await runOn(fx.wow, fx.dist, def: 'eu-x-y');
      expect(r.result.error, '--default "eu-x-y" is not a character id');
      expect(r.result.stop!.code, GatherIssueCode.badDefault);
      expect(r.result.stop!.code.isUsage, isTrue);
    });
  });

  group('screenshots', () {
    test('skips a screenshot that cannot be copied', () async {
      Directory(p.join(fx.dist, mainId)).createSync(recursive: true);
      File(p.join(fx.dist, mainId, 'screenshots')).writeAsStringSync('');
      final r = await runOn(fx.wow, fx.dist);
      expect(r.result.error, isNull);
      expect(r.out, contains('screenshot skipped'));
      expect(
        journey(fx.dist, mainId).where((x) => x.text('screenshot').isNotEmpty),
        isEmpty,
      );
    });

    test('reports a backup copy that fails', () async {
      final shots = p.join(fx.backup, '20261107T120000Z', 'screenshots');
      Directory(p.dirname(shots)).createSync(recursive: true);
      File(shots).writeAsStringSync('');
      final r = await runOn(fx.wow, fx.dist);
      expect(
        r.result.issues.map((i) => i.code),
        contains(GatherIssueCode.backupFailed),
      );
      expect(r.out, contains('warning: backup of '));
    });

    test('a flavor folder without Screenshots matches nothing', () async {
      Directory(p.join(fx.wow, 'Screenshots')).deleteSync(recursive: true);
      final r = await runOn(fx.wow, fx.dist);
      expect(r.result.error, isNull);
      expect(r.out, contains('copied 0 screenshots, 3 not found'));
    });
  });

  group('checks', () {
    test('refuses output folders that overlap the source folders', () async {
      final cases = [
        (p.join(fx.wow, 'Screenshots', 'x'), p.join(fx.wow, 'b')),
        (p.join(fx.wow, 'd'), p.join(fx.wow, 'WTF')),
        (fx.wow, p.join(fx.root, 'b')),
      ];
      for (final (dist, backup) in cases) {
        final r = await runOn(fx.wow, dist, backup: backup);
        expect(r.result.stop?.code, GatherIssueCode.overlap, reason: dist);
        expect(r.result.error, contains('which the converter never writes'));
      }
      expect(Directory(p.join(fx.wow, 'd')).existsSync(), isFalse);
    });

    test('resolves links before the overlap check', () async {
      final link = Link(p.join(fx.root, 'linked'))
        ..createSync(p.join(fx.wow, 'WTF'));
      final r = await runOn(fx.wow, p.join(link.path, 'out'));
      expect(r.result.stop?.code, GatherIssueCode.overlap);
    }, testOn: 'linux || mac-os');

    test('locks the parent of the folder that a backup link names', () async {
      final target = Directory(p.join(fx.root, 'elsewhere', 'b'))
        ..createSync(recursive: true);
      final link = Link(p.join(fx.wow, 'WTF', 'b'))..createSync(target.path);
      final r = await runOn(fx.wow, fx.dist, backup: link.path);
      expect(r.result.error, isNull, reason: r.out);
      expect(File(p.join(fx.wow, 'WTF', '.gather.lock')).existsSync(), isFalse);
      expect(
        File(p.join(fx.root, 'elsewhere', '.gather.lock')).existsSync(),
        isTrue,
      );
    }, testOn: 'linux || mac-os');

    test('refuses a character folder that is a link', () async {
      final outside = Directory(p.join(fx.root, 'outside'))..createSync();
      Directory(fx.dist).createSync();
      final link = Link(p.join(fx.dist, mainId))..createSync(outside.path);
      final r = await runOn(fx.wow, fx.dist);
      expect(r.result.error, '1 characters and 0 accounts failed');
      expect(r.out, contains('is a link'));
      expect(outside.listSync(), isEmpty);

      link.deleteSync();
      Directory(p.join(fx.dist, mainId)).createSync();
      Link(p.join(fx.dist, mainId, 'screenshots')).createSync(outside.path);
      expect((await runOn(fx.wow, fx.dist)).result.error, isNotNull);
      expect(outside.listSync(), isEmpty);
    }, testOn: 'linux || mac-os');

    test('refuses a folder without WTF/Account', () async {
      final r = await runOn(fx.root, p.join(fx.root, 'd'));
      expect(r.result.stop?.code, GatherIssueCode.noWtf);
      expect(r.result.error, contains('no WTF/Account folder'));
      expect(r.result.stop!.code.isUsage, isFalse);
    });

    test('refuses an output folder that cannot be written', () async {
      File(fx.dist).writeAsStringSync('a file, not a folder');
      final r = await runOn(fx.wow, fx.dist);
      expect(r.result.stop?.code, GatherIssueCode.notWritable);
      expect(r.result.files, 0, reason: 'a WoW file was read');
      expect(Directory(fx.backup).listSync(), isEmpty);
    });

    test('refuses a backup root that cannot be created', () async {
      final blocker = File(p.join(fx.root, 'blocker'))..writeAsStringSync('');
      final r = await runOn(
        fx.wow,
        fx.dist,
        backup: p.join(blocker.path, 'backups'),
      );
      expect(r.result.stop?.code, GatherIssueCode.notWritable);
    });

    test(
      'refuses a second gather while another process holds the lock',
      () async {
        final lock = p.join(fx.root, '.gather.lock');
        final holder = await Process.start(Platform.resolvedExecutable, [
          'test/support/hold_lock.dart',
          lock,
        ]);
        addTearDown(holder.kill);
        final lines = holder.stdout.transform(const SystemEncoding().decoder);
        expect(await lines.first, contains('locked'));
        final r = await runOn(fx.wow, fx.dist);
        expect(r.result.stop?.code, GatherIssueCode.lockHeld);
        expect(r.result.error, contains('another gather is running'));
        expect(Directory(fx.dist).existsSync(), isFalse);
        await holder.stdin.close();
        expect(await holder.exitCode, 0);
        expect((await runOn(fx.wow, fx.dist)).result.error, isNull);
      },
    );

    test('the lock refuses a second holder in the same isolate', () {
      final first = GatherLock.acquire(fx.root)!;
      expect(GatherLock.acquire(fx.root), isNull);
      first.release();
      GatherLock.acquire(fx.root)!.release();
    });

    test('reports a folder that cannot be listed', () async {
      final acc = account(fx.wow);
      Process.runSync('chmod', ['000', p.join(acc, 'Brumamar')]);
      addTearDown(
        () => Process.runSync('chmod', ['755', p.join(acc, 'Brumamar')]),
      );
      final r = await runOn(fx.wow, fx.dist);
      expect(r.result.stop?.code, GatherIssueCode.ioError);
    }, testOn: 'linux || mac-os');
  });

  group('helpers', () {
    test('byLevel keys a list by level', () {
      expect(byLevel(['a', 'b']), {'1': 'a', '2': 'b'});
      expect(byLevel('x'), 'x');
    });

    test('charFolder reads both folder layouts', () {
      final cases = [
        ('93', 'Neral-Brumamar', 'Neral', 'Brumamar'),
        ('93', 'Ñandú-Azjol-Nerub', 'Ñandú', 'Azjol-Nerub'),
        ('Brumamar', 'Neral', 'Neral', 'Brumamar'),
        ('Brumamar', '-Neral', '-Neral', 'Brumamar'),
        ('Brumamar', 'Neral-', 'Neral-', 'Brumamar'),
      ];
      for (final (parent, folder, name, realm) in cases) {
        final got = charFolder(parent, folder);
        expect((got.name, got.realm), (name, realm), reason: folder);
      }
    });

    test('regionOf reads the portal of Config.wtf', () {
      final f = File(p.join(fx.wow, 'WTF', 'Config.wtf'));
      expect(regionOf(f), 'eu');
    });

    test('a result without a stop has no error when nothing failed', () {
      const ok = GatherResult();
      expect(ok.stop, isNull);
      expect(ok.error, isNull);
    });
  });
}
