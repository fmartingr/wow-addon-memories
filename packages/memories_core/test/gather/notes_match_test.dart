import 'package:memories_core/memories_core.dart';
import 'package:memories_core/src/gather/match.dart';
import 'package:memories_core/src/gather/notes.dart';
import 'package:test/test.dart';

JournalRecord rec(int t, String k, [Map<String, Object?> kv = const {}]) =>
    JournalRecord({'t': t, 'k': k, ...kv});

List<String> kinds(List<JournalRecord> rs) => [for (final r in rs) r.text('k')];

void main() {
  group('joinNotes', () {
    test('joins by file, two notes on one shot', () {
      final r = joinNotes([
        rec(10, 'ss', {'file': 'A.jpg', 'result': 'ok'}),
        rec(10, 'sn', {'source': 'Paparazzi', 'note': 'one', 'file': 'A.jpg'}),
        rec(11, 'sn', {'source': 'Other', 'note': 'two', 'file': 'A.jpg'}),
      ]);
      expect(r.joined, 2);
      expect(kinds(r.records), ['ss']);
      expect(r.records[0]['notes'], const [
        Note('Paparazzi', 'one'),
        Note('Other', 'two'),
      ]);
    });

    test('joins the nearest free shot', () {
      final r = joinNotes([
        rec(10, 'ss', {'file': 'A.jpg', 'result': 'ok'}),
        rec(11, 'sn', {'source': 'S', 'note': 'near', 'file': 'B.jpg'}),
        rec(12, 'sn', {'source': 'S', 'note': 'taken'}),
        rec(30, 'ss', {'result': 'failed'}),
        rec(31, 'sn', {'source': 'S', 'note': 'failed shot'}),
        rec(50, 'sn', {'source': 'S', 'note': 'alone'}),
      ]);
      expect(r.joined, 1);
      expect(kinds(r.records), ['ss', 'sn', 'ss', 'sn', 'sn']);
      expect(r.records[0]['notes'], const [Note('S', 'near')]);
    });

    test('a tie joins nothing', () {
      final r = joinNotes([
        rec(10, 'ss', {'result': 'ok'}),
        rec(11, 'sn', {'source': 'S', 'note': 'tie'}),
        rec(12, 'ss', {'result': 'ok'}),
      ]);
      expect(r.joined, 0);
      expect(r.records, hasLength(3));
      expect(r.records[0]['notes'], isNull);
      expect(r.records[2]['notes'], isNull);
    });

    test('a note is written as a struct', () {
      const n = Note('S', 'x');
      expect(n.goFields.keys, ['source', 'note']);
      expect(n, const Note('S', 'x'));
      expect(n.hashCode, const Note('S', 'x').hashCode);
      expect('$n', 'Note(S, x)');
    });
  });

  group('fileTime', () {
    test('reads the local time of the name', () {
      expect(fileTime('WoWScrnShot_110626_140309.jpg', 3600), 1793970189);
      final utc = fileTime('WoWScrnShot_110626_140309.jpg', 0)!;
      expect(utc - 1793970189, 3600);
    });

    test('refuses bad names', () {
      for (final bad in [
        'WoWScrnShot_1.jpg',
        'WoWScrnShot_139926_140309.jpg',
        'WoWScrnShot_023026_140309.jpg',
        'WoWScrnShot_110626_240309.jpg',
        'WoWScrnShot_110626_146009.jpg',
        'WoWScrnShot_110626_140360.jpg',
        'WoWScrnShot_110026_140309.jpg',
        'WoWScrnShot_11062a_140309.jpg',
      ]) {
        expect(fileTime(bad, 0), isNull, reason: bad);
      }
      expect(fileTime('WoWScrnShot_022924_000000.jpg', 0), isNotNull);
    });

    test('reads a two-digit year as Go does', () {
      expect(
        fileTime('WoWScrnShot_010170_000000.jpg', 0),
        DateTime.utc(1970).millisecondsSinceEpoch ~/ 1000,
      );
      expect(
        fileTime('WoWScrnShot_010168_000000.jpg', 0),
        DateTime.utc(2068).millisecondsSinceEpoch ~/ 1000,
      );
    });
  });

  group('matchShots', () {
    test('matches by name, else the nearest unclaimed file', () {
      const tz = 3600;
      final base = fileTime('WoWScrnShot_110626_140309.jpg', tz)!;
      final files = [
        'WoWScrnShot_110626_140309.jpg',
        'WoWScrnShot_110626_140308.jpg',
        'WoWScrnShot_110626_150000.jpg',
        'WoWScrnShot_110626_150002.jpg',
        'WoWScrnShot_110626_160000.jpg',
      ];
      final t15 = fileTime('WoWScrnShot_110626_150001.jpg', tz)!;
      final t16 = fileTime('WoWScrnShot_110626_160000.jpg', tz)!;
      final shots = [
        Shot(
          file: 'WoWScrnShot_110626_140309.jpg',
          t: base,
          tz: tz,
          hasTz: true,
        ),
        Shot(
          file: 'WoWScrnShot_110626_140310.jpg',
          t: base + 1,
          tz: tz,
          hasTz: true,
        ),
        Shot(
          file: 'WoWScrnShot_110626_150001.jpg',
          t: t15,
          tz: tz,
          hasTz: true,
        ),
        Shot(file: 'WoWScrnShot_110626_160001.jpg', t: t16 + 1, hasTz: false),
        Shot(
          file: 'WoWScrnShot_110626_170000.jpg',
          t: t16 + 3600,
          tz: tz,
          hasTz: true,
        ),
        const Shot(file: 'WoWScrnShot_110626_160000.jpg', t: 0, hasTz: false),
      ];
      final claimed = {'WoWScrnShot_110626_160000.jpg'};
      expect(matchShots(shots, files, claimed), [0, 1, -1, -1, -1, -1]);
      expect(claimed, contains('WoWScrnShot_110626_140308.jpg'));
      expect(claimed, isNot(contains('WoWScrnShot_110626_150000.jpg')));
    });

    test('uses the time zone of the session', () {
      final files = ['WoWScrnShot_110626_140309.jpg'];
      final utc = fileTime(files[0], 0)!;
      expect(
        matchShots(
          [Shot(file: 'x', t: utc - 7200, tz: 7200, hasTz: true)],
          files,
          {},
        ),
        [0],
      );
      expect(
        matchShots([Shot(file: 'x', t: utc - 7200, hasTz: true)], files, {}),
        [-1],
        reason: 'a wrong zone matched',
      );
    });

    test('the name pattern accepts only game screenshots', () {
      expect(fileNamePattern.hasMatch('WoWScrnShot_110626_140309.jpg'), isTrue);
      expect(fileNamePattern.hasMatch('WoWScrnShot_110626_140309.tga'), isTrue);
      expect(
        fileNamePattern.hasMatch('WoWScrnShot_110626_140309.gif'),
        isFalse,
      );
      expect(fileNamePattern.hasMatch('x_110626_140309.jpg'), isFalse);
    });
  });

  test('sortStable keeps the order of equal items', () {
    final list = [(1, 'a'), (0, 'b'), (1, 'c'), (0, 'd')];
    sortStable(list, (x, y) => x.$1.compareTo(y.$1));
    expect(list, [(0, 'b'), (0, 'd'), (1, 'a'), (1, 'c')]);
  });

  test('searchFirst finds the first true index', () {
    final xs = [1, 3, 5, 7];
    expect(searchFirst(xs.length, (i) => xs[i] >= 4), 2);
    expect(searchFirst(xs.length, (i) => xs[i] >= 9), 4);
    expect(searchFirst(xs.length, (i) => xs[i] >= 0), 0);
  });
}
