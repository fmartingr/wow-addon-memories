import 'dart:io';

import 'package:memories_core/memories_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fixture.dart';

void main() {
  late ({String root, String wow, String dist, String backup}) fx;
  late String account;
  late String character;

  setUp(() {
    fx = copyFixture();
    account = p.join(fx.wow, 'WTF', 'Account', 'TESTACCOUNT');
    character = p.join(account, 'Brumamar', 'Ñandú', 'SavedVariables');
  });

  tearDown(() => Directory(fx.root).deleteSync(recursive: true));

  Future<String?> sign() => signature(Directory(fx.wow));

  test('the fixture has a stable SHA-256 signature', () async {
    final first = await sign();
    expect(first, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(await sign(), first);
  });

  test('the fixture itself is read in place and left as it was', () async {
    final before = readTree(fixtureWow);
    expect(await signature(Directory(fixtureWow)), isNotNull);
    expect(readTree(fixtureWow), before);
  });

  test('a size change changes the signature', () async {
    final before = await sign();
    final file = File(p.join(character, 'Memories_Combat.lua'));
    final mtime = file.lastModifiedSync();
    file.writeAsStringSync('-- more\n', mode: FileMode.append);
    file.setLastModifiedSync(mtime);
    expect(await sign(), isNot(before));
  });

  test('a modification time change changes the signature', () async {
    final before = await sign();
    final file = File(p.join(account, 'SavedVariables', 'Memories.lua'));
    file.setLastModifiedSync(
      file.lastModifiedSync().add(const Duration(seconds: 3)),
    );
    expect(await sign(), isNot(before));
  });

  test('a new file of a character changes the signature', () async {
    final before = await sign();
    File(p.join(character, 'Memories_Social.lua')).writeAsStringSync('x');
    expect(await sign(), isNot(before));
  });

  test('a new account changes the signature', () async {
    final before = await sign();
    final sv = Directory(
      p.join(fx.wow, 'WTF', 'Account', 'OTHER', 'SavedVariables'),
    )..createSync(recursive: true);
    File(p.join(sv.path, 'Memories.lua')).writeAsStringSync('x');
    expect(await sign(), isNot(before));
  });

  test('a deleted file changes the signature', () async {
    final before = await sign();
    File(p.join(character, 'Memories_Gathering.lua')).deleteSync();
    expect(await sign(), isNot(before));
  });

  test('other files and folders do not count', () async {
    final before = await sign();
    File(p.join(character, 'Memories.lua.bak')).writeAsStringSync('x');
    File(p.join(character, 'Blizzard_Stuff.lua')).writeAsStringSync('x');
    File(p.join(character, 'MemoriesPlus.lua')).writeAsStringSync('x');
    File(p.join(character, 'Memories_Foo-Bar.lua')).writeAsStringSync('x');
    File(p.join(account, 'Memories.lua')).writeAsStringSync('x');
    File(p.join(fx.wow, 'WTF', 'Config.wtf')).writeAsStringSync('x');
    // A gather skips a realm folder named SavedVariables.
    final nested = Directory(
      p.join(account, 'SavedVariables', 'Nested', 'SavedVariables'),
    )..createSync(recursive: true);
    File(p.join(nested.path, 'Memories.lua')).writeAsStringSync('x');
    expect(await sign(), before);
  });

  test('a flavor folder that is gone gives null', () async {
    expect(await signature(Directory(p.join(fx.root, 'gone'))), isNull);
  });

  test('a folder with no Memories file gives null', () async {
    for (final f in Directory(fx.wow).listSync(recursive: true)) {
      if (f is File && p.basename(f.path).startsWith('Memories')) {
        f.deleteSync();
      }
    }
    expect(await sign(), isNull);
  });

  test('links are never followed', () async {
    final before = await sign();
    final outside = Directory(p.join(fx.root, 'outside', 'SavedVariables'))
      ..createSync(recursive: true);
    File(p.join(outside.path, 'Memories.lua')).writeAsStringSync('x');
    final accounts = p.join(fx.wow, 'WTF', 'Account');
    Link(p.join(accounts, 'LINKED')).createSync(outside.parent.path);
    Link(p.join(character, 'Memories_Linked.lua'))
        .createSync(p.join(outside.path, 'Memories.lua'));
    Link(p.join(account, 'Brumamar', 'Other')).createSync(outside.parent.path);
    expect(await sign(), before);
  }, skip: Platform.isWindows ? 'links need admin rights on Windows' : false);

  test('a linked account folder gives null', () async {
    final wtf = p.join(fx.wow, 'WTF');
    final moved = p.join(fx.root, 'Account');
    Directory(p.join(wtf, 'Account')).renameSync(moved);
    Link(p.join(wtf, 'Account')).createSync(moved);
    expect(await sign(), isNull);
  }, skip: Platform.isWindows ? 'links need admin rights on Windows' : false);
}
