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

  test('unselect forgets what was sent and drops the selection', () {
    final site = UploadState.empty().site(a)
      ..select(['wow/eu/r/a', 'wow/eu/r/z'])
      ..sent['wow/eu/r/z'] = '1'
      ..shots['wow/eu/r/z'] = {'f': 'g'};
    site.unselect('wow/eu/r/z');
    expect(site.sent, isEmpty);
    expect(site.shots, isEmpty);
    expect(site.selected, {'wow/eu/r/a'});
  });

  test('the selection round trips, sorted, even when it is empty', () {
    final s = UploadState.empty();
    s.site(a).select(['wow/eu/r/z', 'wow/eu/r/a']);
    s.site(b).select([]);
    s.save(file);
    final sites = (jsonDecode(file.readAsStringSync()) as Map)['sites'] as Map;
    expect(sites['https://a.example']['selected'], [
      'wow/eu/r/a',
      'wow/eu/r/z',
    ]);
    expect(sites['https://b.example']['selected'], <String>[]);
    final back = UploadState.load(file);
    expect(back.site(a).selected, {'wow/eu/r/a', 'wow/eu/r/z'});
    expect(back.site(b).selected, isEmpty);
    expect(back.site(b).selectionSet, isTrue);
  });

  test('a site that never had a selection writes none', () {
    final s = UploadState.empty();
    s.site(a).registered = true;
    expect(s.site(a).selected, isEmpty);
    s.save(file);
    final json = jsonDecode(file.readAsStringSync()) as Map;
    expect((json['sites'] as Map)['https://a.example'], {
      'registered': true,
      'screenshotsApproved': false,
      'sent': <String, Object?>{},
      'shots': <String, Object?>{},
    });
  });

  test('a file with no selection selects the characters it already sent', () {
    file.writeAsStringSync(
      jsonEncode({
        'v': 1,
        'sites': {
          'https://a.example': {
            'registered': true,
            'screenshotsApproved': false,
            'sent': {'wow/eu/r/a': '1', 'wow/eu/r/b': '2'},
            'shots': <String, Object?>{},
          },
          'https://b.example': {'registered': true},
        },
      }),
    );
    final s = UploadState.load(file);
    expect(s.site(a).selected, {'wow/eu/r/a', 'wow/eu/r/b'});
    expect(s.site(b).selected, isEmpty);
    s.save(file);
    final back = UploadState.load(file);
    expect(back.site(a).selected, {'wow/eu/r/a', 'wow/eu/r/b'});
  });

  test('a stored selection is not widened by what was sent', () {
    file.writeAsStringSync(
      jsonEncode({
        'v': 1,
        'sites': {
          'https://a.example': {
            'sent': {'wow/eu/r/a': '1', 'wow/eu/r/b': '2'},
            'selected': ['wow/eu/r/a'],
          },
        },
      }),
    );
    expect(UploadState.load(file).site(a).selected, {'wow/eu/r/a'});
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
            'selected': ['wow/eu/r/n', 3],
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
    expect(s.site(a).selected, {'wow/eu/r/n'});
    expect(s.site(b).registered, isFalse);
    expect(s.site(b).selected, isEmpty);
  });

  test('a selected field that is not a list counts as no selection', () {
    file.writeAsStringSync(
      jsonEncode({
        'v': 1,
        'sites': {
          'https://a.example': {
            'selected': 'wow/eu/r/n',
            'sent': {'wow/eu/r/m': '1'},
          },
        },
      }),
    );
    expect(UploadState.load(file).site(a).selected, {'wow/eu/r/m'});
  });

  test('the removed field of the earlier format is ignored', () {
    file.writeAsStringSync(
      jsonEncode({
        'v': 1,
        'sites': {
          'https://a.example': {
            'removed': ['wow/eu/r/n'],
            'sent': {'wow/eu/r/m': '1'},
          },
        },
      }),
    );
    final s = UploadState.load(file);
    expect(s.site(a).selected, {'wow/eu/r/m'});
    s.save(file);
    expect(file.readAsStringSync(), isNot(contains('removed')));
  });

  test('a file that is not UTF-8 text starts fresh with a warning', () {
    file.writeAsBytesSync([0xff, 0xfe, 0x00, 0x7b]);
    final s = UploadState.load(file);
    expect(s.warning, contains('damaged'));
    expect(s.site(a).sent, isEmpty);
  });

  test('forgetKey unregisters every site and keeps the selection', () {
    final s = UploadState.empty();
    for (final site in [a, b]) {
      s.site(site)
        ..registered = true
        ..screenshotsApproved = true
        ..sent['wow/eu/r/n'] = 'abc'
        ..shots['wow/eu/r/n'] = {'f.jpg': 'def'}
        ..select(['wow/eu/r/z']);
    }
    s.forgetKey();
    s.save(file);
    final back = UploadState.load(file);
    for (final site in [a, b]) {
      expect(back.site(site).registered, isFalse);
      expect(back.site(site).screenshotsApproved, isFalse);
      expect(back.site(site).sent, isEmpty);
      expect(back.site(site).shots, isEmpty);
      expect(back.site(site).selected, {'wow/eu/r/z'});
    }
  });
}
