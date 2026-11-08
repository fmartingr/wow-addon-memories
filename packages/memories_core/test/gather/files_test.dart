import 'dart:io';

import 'package:memories_core/src/gather/files.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late String dir;

  setUp(
    () => dir = Directory.systemTemp.createTempSync('memories-files-').path,
  );
  tearDown(() => Directory(dir).deleteSync(recursive: true));

  group('copyFile', () {
    test('copies once, keeps the time, refuses links and missing files', () {
      final src = File(p.join(dir, 'src.jpg'))..writeAsStringSync('img');
      final when = DateTime(2026, 1, 2, 3, 4, 5);
      src.setLastModifiedSync(when);
      final dst = p.join(dir, 'out', 'a.jpg');
      expect(copyFile(src.path, dst), isTrue);
      expect(File(dst).readAsStringSync(), 'img');
      expect(File(dst).lastModifiedSync(), when);
      expect(copyFile(src.path, dst), isFalse);

      final link = Link(p.join(dir, 'link.jpg'))..createSync(src.path);
      expect(
        () => copyFile(link.path, p.join(dir, 'b.jpg')),
        throwsA(isA<FileSystemException>()),
      );
      expect(
        () => copyFile(p.join(dir, 'none'), p.join(dir, 'c.jpg')),
        throwsA(isA<FileSystemException>()),
      );
      expect(Directory(dir).listSync().map((e) => p.basename(e.path)), {
        'src.jpg',
        'out',
        'link.jpg',
      });
    }, testOn: 'linux || mac-os');
  });

  group('writeAtomic', () {
    test('replaces the file and leaves no temporary file', () {
      final path = p.join(dir, 'a', 'b.json');
      writeAtomic(path, [1, 2]);
      writeAtomic(path, [3]);
      expect(File(path).readAsBytesSync(), [3]);
      expect(Directory(p.dirname(path)).listSync(), hasLength(1));
    });

    test('removes the temporary file when the rename fails', () {
      final target = Directory(p.join(dir, 'taken'))..createSync();
      File(p.join(target.path, 'x')).writeAsStringSync('keep');
      expect(
        () => writeAtomic(target.path, [1]),
        throwsA(isA<FileSystemException>()),
      );
      expect(Directory(dir).listSync().map((e) => p.basename(e.path)), [
        'taken',
      ]);
    });

    test('writes JSON lines', () {
      final path = p.join(dir, 'rows.jsonl');
      writeJsonl(path, [
        {'b': 1, 'a': 2},
        [1],
      ]);
      expect(File(path).readAsStringSync(), '{"a":2,"b":1}\n[1]\n');
    });
  });

  group('readers', () {
    Object? any(Object? row) => row;

    test('a missing file has no rows', () {
      expect(readJsonl(p.join(dir, 'none.jsonl'), any), isEmpty);
      expect(readJson(p.join(dir, 'none.json')), isNull);
    });

    test('a damaged file is refused', () {
      final bad = File(p.join(dir, 'bad.jsonl'))
        ..writeAsStringSync('{"t":1}\n\n{nope\n');
      expect(
        () => readJsonl(bad.path, any),
        throwsA(
          isA<OutputFileException>().having(
            (e) => '$e',
            'text',
            startsWith('${bad.path} line 3: '),
          ),
        ),
      );
      bad.writeAsStringSync('[1]');
      expect(() => readJson(bad.path), throwsA(isA<OutputFileException>()));
      bad.writeAsStringSync('{nope');
      expect(() => readJson(bad.path), throwsA(isA<OutputFileException>()));
      expect(() => readJson(dir), throwsA(isA<FileSystemException>()));
      expect(() => readJsonl(dir, any), throwsA(isA<FileSystemException>()));
    });

    test('reads rows, the null object and CRLF lines', () {
      final f = File(p.join(dir, 'rows.jsonl'))
        ..writeAsStringSync('{"t":1}\r\n  \n{"t":2}');
      expect(readJsonl(f.path, any), [
        {'t': 1},
        {'t': 2},
      ]);
      f.writeAsStringSync('null');
      expect(readJson(f.path), isNull);
      f.writeAsBytesSync([
        0x7b,
        0x22,
        0x61,
        0x22,
        0x3a,
        0x22,
        0xff,
        0x22,
        0x7d,
      ]);
      expect(readJson(f.path), {'a': '\ufffd'});
    });

    test('a row of the wrong form names its line', () {
      final f = File(p.join(dir, 'rows.jsonl'))..writeAsStringSync('\n[1]\n');
      expect(
        () => readJsonl(f.path, (row) => throw const FormatException('nope')),
        throwsA(
          isA<OutputFileException>().having(
            (e) => e.message,
            'message',
            '${f.path} line 2: nope',
          ),
        ),
      );
    });
  });

  group('inside', () {
    test('resolves links and ignores case', () {
      final wtf = p.join(dir, 'wow', 'WTF');
      Directory(wtf).createSync(recursive: true);
      final link = Link(p.join(dir, 'elsewhere'))..createSync(wtf);
      final cases = {
        wtf: true,
        p.join(wtf, 'a', 'b'): true,
        p.join(link.path, 'new'): true,
        p.join(dir, 'wow', 'wtf', 'x'): true,
        p.join(dir, 'wow', 'WTF2'): false,
        p.join(dir, 'wow'): false,
        p.join(dir, 'dist-out', 'x'): false,
      };
      cases.forEach((path, want) {
        expect(inside(path, wtf), want, reason: path);
      });
    }, testOn: 'linux || mac-os');

    test('compares Windows paths', () {
      final w = p.Context(style: p.Style.windows);
      expect(
        isWithinIgnoringCase(
          r'C:\Games\WoW\_forever_\WTF\out',
          r'c:\games\wow\_forever_\wtf',
          style: w,
        ),
        isTrue,
      );
      expect(
        isWithinIgnoringCase(
          r'C:\Games\WoW\_forever_\WTF2',
          r'C:\Games\WoW\_forever_\WTF',
          style: w,
        ),
        isFalse,
      );
      expect(isWithinIgnoringCase(r'D:\WTF', r'D:\wtf\', style: w), isTrue);
    });

    test('resolveLinks keeps the missing part of a path', () {
      final real = Directory(p.join(dir, 'real'))..createSync();
      final link = Link(p.join(dir, 'l'))..createSync(real.path);
      expect(
        resolveLinks(p.join(link.path, 'a', 'b')),
        p.join(real.resolveSymbolicLinksSync(), 'a', 'b'),
      );
    }, testOn: 'linux || mac-os');
  });
}
