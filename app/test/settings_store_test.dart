import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wow_journey/src/settings/settings.dart';
import 'package:wow_journey/src/settings/settings_controller.dart';
import 'package:wow_journey/src/settings/settings_store.dart';

import 'support/fakes.dart';

void main() {
  late Directory dir;
  late FileSettingsStore store;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wow_journey_settings_');
    store = FileSettingsStore(() async => dir.path);
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  File file() => File(p.join(dir.path, 'settings.json'));

  test('the defaults have Watch and Start at login on', () {
    const s = Settings();
    expect(s.watch, isTrue);
    expect(s.startAtLogin, isTrue);
    expect(s.wizardDone, isFalse);
    expect(s.flavorDir, isNull);
    expect(s.backupRoot, isNull);
  });

  test('the defaults have the default website and Upload off', () {
    const s = Settings();
    expect(s.site, defaultSite);
    expect(s.site, startsWith('https://'));
    expect(s.upload, isFalse);
  });

  test('a missing file gives the defaults and no notice', () async {
    final loaded = await store.load();
    expect(loaded.settings, const Settings());
    expect(loaded.notice, isNull);
  });

  test('a saved value reads back the same', () async {
    const s = Settings(
      flavorDir: '/wow/_retail_',
      backupRoot: '/backups',
      watch: false,
      startAtLogin: false,
      wizardDone: true,
      lastSignature: 'abc',
      site: 'http://localhost:8080',
      upload: true,
    );
    await store.save(s);
    final loaded = await store.load();
    expect(loaded.settings, s);
    expect(loaded.notice, isNull);
  });

  group('language', () {
    test('the default follows the system', () {
      expect(const Settings().language, isNull);
    });

    test('a chosen language reads back the same', () async {
      await store.save(const Settings(language: 'pt'));
      expect(file().readAsStringSync(), contains('"language": "pt"'));
      final loaded = await store.load();
      expect(loaded.settings.language, 'pt');
      expect(loaded.notice, isNull);
    });

    test('System is saved as null and reads back as System', () async {
      await store.save(const Settings());
      expect(file().readAsStringSync(), contains('"language": null'));
      expect((await store.load()).settings.language, isNull);
    });

    for (final (name, json) in [
      ('a file without the key', '{"watch": false}'),
      ('an unsupported code', '{"language": "ru"}'),
      ('an empty text', '{"language": ""}'),
      ('a number', '{"language": 3}'),
      ('a list', '{"language": ["de"]}'),
    ]) {
      test('$name loads as System with no notice', () async {
        file().writeAsStringSync(json);
        final loaded = await store.load();
        expect(loaded.settings.language, isNull);
        expect(loaded.notice, isNull);
      });
    }

    test('copyWith sets, keeps and clears the language', () {
      const s = Settings(language: 'fr');
      expect(s.copyWith(watch: false).language, 'fr');
      expect(s.copyWith(language: 'es').language, 'es');
      expect(s.copyWith(clearLanguage: true).language, isNull);
      expect(s.copyWith(language: 'ru').language, 'fr');
    });

    test('the language is part of the equality', () {
      expect(const Settings(language: 'de'), const Settings(language: 'de'));
      expect(
        const Settings(language: 'de'),
        isNot(const Settings(language: 'fr')),
      );
    });
  });

  test('a save replaces the file and leaves no temporary file', () async {
    await store.save(const Settings(backupRoot: '/one'));
    await store.save(const Settings(backupRoot: '/two'));
    expect((await store.load()).settings.backupRoot, '/two');
    expect(dir.listSync().map((e) => p.basename(e.path)), ['settings.json']);
  });

  test('a save creates the missing support folder', () async {
    final nested = p.join(dir.path, 'a', 'b');
    final s = FileSettingsStore(() async => nested);
    await s.save(const Settings(wizardDone: true));
    expect(File(p.join(nested, 'settings.json')).existsSync(), isTrue);
  });

  test('a failed save keeps the old file whole', () async {
    await store.save(const Settings(backupRoot: '/old'));
    final before = file().readAsStringSync();
    Process.runSync('chmod', ['555', dir.path]);
    addTearDown(() => Process.runSync('chmod', ['755', dir.path]));
    await expectLater(
      store.save(const Settings(backupRoot: '/new')),
      throwsA(isA<FileSystemException>()),
    );
    expect(file().readAsStringSync(), before);
    expect(dir.listSync(), hasLength(1));
  }, skip: Platform.isWindows ? 'chmod is not on Windows' : null);

  for (final (name, text) in [
    ('text that is not JSON', '{"watch": tru'),
    ('a list', '[1, 2]'),
    ('a value of the wrong type', '{"watch": "yes"}'),
    ('an empty file', ''),
  ]) {
    test('a damaged file ($name) gives the defaults and a notice', () async {
      file().writeAsStringSync(text);
      final loaded = await store.load();
      expect(loaded.settings, const Settings());
      expect(loaded.notice, SettingsNotice.damaged);
    });
  }

  test('a file that is not UTF-8 gives the defaults and a notice', () async {
    file().writeAsBytesSync([0xff, 0xfe, 0x00]);
    final loaded = await store.load();
    expect(loaded.settings, const Settings());
    expect(loaded.notice, SettingsNotice.damaged);
  });

  test('a missing key takes its default', () async {
    file().writeAsStringSync('{"wizardDone": true}');
    final loaded = await store.load();
    expect(loaded.settings, const Settings(wizardDone: true));
  });

  test(
    'a file with no website keys keeps its values and the defaults',
    () async {
      file().writeAsStringSync('{"wizardDone": true, "watch": false}');
      final loaded = await store.load();
      expect(loaded.settings.watch, isFalse);
      expect(loaded.settings.site, defaultSite);
      expect(loaded.settings.upload, isFalse);
    },
  );

  test('a site or upload value of the wrong type is a damaged file', () async {
    for (final text in ['{"site": 3}', '{"upload": "yes"}']) {
      file().writeAsStringSync(text);
      final loaded = await store.load();
      expect(loaded.settings, const Settings());
      expect(loaded.notice, SettingsNotice.damaged);
    }
  });

  test('copyWith changes the site and the Upload switch', () {
    final s = const Settings().copyWith(
      site: 'https://example.com',
      upload: true,
    );
    expect(s.site, 'https://example.com');
    expect(s.upload, isTrue);
    expect(s.copyWith(upload: false).site, 'https://example.com');
  });

  group('SettingsController', () {
    test('load gives the settings and the notice of the store', () async {
      final fake = FakeSettingsStore((
        settings: readySettings,
        notice: SettingsNotice.damaged,
      ));
      final c = SettingsController(fake);
      expect(c.loaded, isFalse);
      await c.load();
      expect(c.loaded, isTrue);
      expect(c.settings, readySettings);
      expect(c.notice, SettingsNotice.damaged);
      c.dismissNotice();
      expect(c.notice, isNull);
    });

    test('update saves and notifies', () async {
      final fake = FakeSettingsStore();
      final c = SettingsController(fake);
      var notified = 0;
      c.addListener(() => notified++);
      expect(await c.update(readySettings), isTrue);
      expect(fake.saved, [readySettings]);
      expect(c.settings, readySettings);
      expect(notified, 1);
    });

    test(
      'a failed save keeps the value for this run and tells the user',
      () async {
        final fake = FakeSettingsStore()..failSave = true;
        final c = SettingsController(fake);
        expect(await c.update(readySettings), isFalse);
        expect(c.settings, readySettings);
        expect(c.notice, SettingsNotice.saveFailed);
      },
    );
  });
}
