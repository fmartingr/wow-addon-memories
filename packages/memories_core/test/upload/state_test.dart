import 'dart:convert';
import 'dart:io';

import 'package:memories_core/memories_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tmp;
  late File file;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('memories-state-');
    file = File(p.join(tmp.path, 'state.json'));
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  final a = Uri.parse('https://a.example');
  final b = Uri.parse('https://b.example');

  test('a missing file is an empty state with no warning', () {
    final s = UploadState.load(file);
    expect(s.warning, isNull);
    expect(s.site(a).registered, isFalse);
  });

  test('the state round trips and each site keeps its own record', () {
    final s = UploadState.empty();
    s.site(a)
      ..registered = true
      ..screenshotsApproved = true
      ..sent['wow/eu/r/n'] = 'abc'
      ..shots['wow/eu/r/n'] = {'f.jpg': 'def'};
    s.save(file);
    final back = UploadState.load(file);
    expect(back.site(a).registered, isTrue);
    expect(back.site(a).screenshotsApproved, isTrue);
    expect(back.site(a).sent, {'wow/eu/r/n': 'abc'});
    expect(back.site(a).shots['wow/eu/r/n'], {'f.jpg': 'def'});
    expect(back.site(b).registered, isFalse);
    expect(back.site(b).sent, isEmpty);
    expect((jsonDecode(file.readAsStringSync()) as Map)['v'], 1);
  });

  test('forget drops what was sent for one character', () {
    final site = UploadState.empty().site(a)
      ..sent['x'] = '1'
      ..sent['y'] = '2'
      ..shots['x'] = {'f': 'g'};
    site.forget('x');
    expect(site.sent, {'y': '2'});
    expect(site.shots, isEmpty);
  });

  test('the removed set round trips, sorted, and markRemoved forgets', () {
    final s = UploadState.empty();
    s.site(a)
      ..sent['wow/eu/r/z'] = '1'
      ..shots['wow/eu/r/z'] = {'f': 'g'}
      ..markRemoved('wow/eu/r/z')
      ..markRemoved('wow/eu/r/a');
    expect(s.site(a).sent, isEmpty);
    expect(s.site(a).shots, isEmpty);
    s.save(file);
    final json = jsonDecode(file.readAsStringSync()) as Map;
    expect((json['sites'] as Map)['https://a.example']['removed'], [
      'wow/eu/r/a',
      'wow/eu/r/z',
    ]);
    expect(UploadState.load(file).site(a).removed, {
      'wow/eu/r/a',
      'wow/eu/r/z',
    });
  });

  test('an empty removed set is not written, and old files load', () {
    final s = UploadState.empty();
    s.site(a).registered = true;
    s.save(file);
    final json = jsonDecode(file.readAsStringSync()) as Map;
    expect((json['sites'] as Map)['https://a.example'], {
      'registered': true,
      'screenshotsApproved': false,
      'sent': <String, Object?>{},
      'shots': <String, Object?>{},
    });
    expect(UploadState.load(file).site(a).removed, isEmpty);
  });

  test('a damaged file starts fresh with a warning', () {
    for (final text in ['nope', '[]', '{"v": 2, "sites": {}}', '{"v": 1}']) {
      file.writeAsStringSync(text);
      final s = UploadState.load(file);
      expect(s.warning, contains('damaged'), reason: text);
      expect(s.site(a).sent, isEmpty);
    }
  });

  test('fields of the wrong type fall back to their defaults', () {
    file.writeAsStringSync(
      jsonEncode({
        'v': 1,
        'sites': {
          'https://a.example': {
            'registered': 'yes',
            'sent': {'x': 1, 'y': 'ok'},
            'removed': ['wow/eu/r/n', 3],
            'shots': {
              'x': 5,
              'z': {'f': 'g', 'h': 2},
            },
          },
          'https://b.example': 7,
        },
      }),
    );
    final s = UploadState.load(file);
    expect(s.warning, isNull);
    expect(s.site(a).registered, isFalse);
    expect(s.site(a).sent, {'y': 'ok'});
    expect(s.site(a).shots, {
      'x': <String, String>{},
      'z': {'f': 'g'},
    });
    expect(s.site(a).removed, {'wow/eu/r/n'});
    expect(s.site(b).registered, isFalse);
    expect(s.site(b).removed, isEmpty);
  });

  test('a removed field that is not a list is an empty set', () {
    file.writeAsStringSync(
      jsonEncode({
        'v': 1,
        'sites': {
          'https://a.example': {'removed': 'wow/eu/r/n'},
        },
      }),
    );
    expect(UploadState.load(file).site(a).removed, isEmpty);
  });

  test('a file that is not UTF-8 text starts fresh with a warning', () {
    file.writeAsBytesSync([0xff, 0xfe, 0x00, 0x7b]);
    final s = UploadState.load(file);
    expect(s.warning, contains('damaged'));
    expect(s.site(a).sent, isEmpty);
  });
}
