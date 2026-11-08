import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memories_core/memories_core.dart';
import 'package:path/path.dart' as p;
import 'package:wow_journey/src/gather/gather_controller.dart';

import 'support/fakes.dart';

/// The fixture flavor folder, relative to `app/` where the tests run.
const String fixtureWow = '../testdata/wow';

void main() {
  group('GatherController', () {
    test('goes idle, running, done and keeps the result', () async {
      final service = FakeGatherService()..pending = Completer<GatherReport>();
      final finished = DateTime(2026, 11, 8, 14, 32);
      final c = GatherController(service, clock: () => finished);
      final states = <GatherState>[];
      c.addListener(() => states.add(c.state));
      expect(c.state, GatherState.idle);

      final run = c.gatherNow(flavorDir: retailDir, backupRoot: '/root');
      expect(c.state, GatherState.running);
      expect(c.running, isTrue);

      const snap = BackupSnapshot(
        characters: [CharacterSummary(id: 'a', name: 'A', realm: 'R')],
      );
      service.pending!.complete((
        result: const GatherResult(characters: 1, lines: 3, screenshots: 2),
        snapshot: snap,
      ));
      final result = await run;

      expect(result!.characters, 1);
      expect(states, [GatherState.running, GatherState.done]);
      expect(c.snapshot, same(snap));
      expect(c.lastGathered, finished);
      expect(c.issues, isEmpty);
      expect(service.calls, [(retailDir, '/root')]);
    });

    test('a second gather while one runs does nothing', () async {
      final service = FakeGatherService()..pending = Completer<GatherReport>();
      final c = GatherController(service);
      final first = c.gatherNow(flavorDir: retailDir, backupRoot: '/root');
      expect(
        await c.gatherNow(flavorDir: retailDir, backupRoot: '/root'),
        isNull,
      );
      service.pending!.complete((
        result: const GatherResult(),
        snapshot: const BackupSnapshot(),
      ));
      await first;
      expect(service.calls, hasLength(1));
    });

    test('a fatal issue gives failed', () async {
      final service = FakeGatherService()
        ..next = (
          result: GatherResult(
            issues: [issue(GatherIssueCode.noData, fatal: true)],
          ),
          snapshot: const BackupSnapshot(),
        );
      final c = GatherController(service);
      await c.gatherNow(flavorDir: retailDir, backupRoot: '/root');
      expect(c.state, GatherState.failed);
      expect(c.issues.single.code, GatherIssueCode.noData);
    });

    test('issues that are not fatal give done', () async {
      final service = FakeGatherService()
        ..next = (
          result: GatherResult(
            characters: 1,
            issues: [issue(GatherIssueCode.damagedFile)],
          ),
          snapshot: const BackupSnapshot(),
        );
      final c = GatherController(service);
      await c.gatherNow(flavorDir: retailDir, backupRoot: '/root');
      expect(c.state, GatherState.done);
      expect(c.issues, hasLength(1));
    });

    test('an error of the service never reaches the caller', () async {
      final service = FakeGatherService()..error = StateError('boom');
      final c = GatherController(service);
      final result = await c.gatherNow(
        flavorDir: retailDir,
        backupRoot: '/root',
      );
      expect(c.state, GatherState.failed);
      expect(result!.stop!.code, GatherIssueCode.ioError);
      expect(c.running, isFalse);
    });

    test(
      'refresh reads the snapshot; the last time is the newest backup',
      () async {
        final t = DateTime(2026, 11, 7, 9);
        final service = FakeGatherService(
          snapshot: BackupSnapshot(lastGathered: t, sizeBytes: 10),
        );
        final c = GatherController(service);
        await c.refresh('/root');
        expect(service.inspected, ['/root']);
        expect(c.snapshot.sizeBytes, 10);
        expect(c.lastGathered, t);
        expect(c.state, GatherState.idle);
      },
    );
  });

  group('GatherController with a new backup root', () {
    test('a gather of the old root that ends late is dropped', () async {
      final service = FakeGatherService(
        snapshot: const BackupSnapshot(sizeBytes: 1),
      )..pending = Completer<GatherReport>();
      final c = GatherController(service);
      final run = c.gatherNow(flavorDir: retailDir, backupRoot: '/old');
      await c.refresh('/new');
      service.pending!.complete((
        result: const GatherResult(characters: 2),
        snapshot: const BackupSnapshot(sizeBytes: 99),
      ));
      await run;

      expect(c.snapshot.sizeBytes, 1);
      expect(c.state, GatherState.idle);
      expect(c.result, isNull);
    });

    test('forget drops the last result', () async {
      final service = FakeGatherService()
        ..next = (
          result: GatherResult(
            issues: [issue(GatherIssueCode.noWtf, fatal: true)],
          ),
          snapshot: const BackupSnapshot(),
        );
      final c = GatherController(service);
      await c.gatherNow(flavorDir: retailDir, backupRoot: '/root');
      expect(c.issues, hasLength(1));

      c.forget();
      expect(c.issues, isEmpty);
      expect(c.state, GatherState.idle);
    });
  });

  group('gatherInto', () {
    late Directory tmp;

    setUp(
      () => tmp = Directory.systemTemp.createTempSync('wow_journey_gather_'),
    );
    tearDown(() => tmp.deleteSync(recursive: true));

    test('gathers the fixture and reads the backup root back', () async {
      final root = p.join(tmp.path, 'WoW Journey');
      expect(Directory(root).existsSync(), isFalse);

      final report = await gatherInto(fixtureWow, root);

      expect(report.result.stop, isNull);
      expect(report.result.characters, 2);
      expect(report.result.lines, 16);
      expect(report.result.screenshots, 2);
      expect(File(p.join(root, 'latest', 'index.json')).existsSync(), isTrue);
      expect(Directory(p.join(root, 'backups')).listSync(), hasLength(1));
      final snap = report.snapshot;
      expect(snap.characters.map((c) => c.realm), ['Brumamar', 'Los Errantes']);
      expect(snap.characters.first.name, 'Ñandú');
      expect(snap.characters.first.level, 10);
      expect(snap.characters.first.className, 'HUNTER');
      expect(snap.lines, 16);
      expect(snap.screenshots, 2);
      expect(snap.lastGathered, isNotNull);
      expect(snap.sizeBytes, greaterThan(0));
    });

    test('runs in an isolate with plain values', () async {
      final root = p.join(tmp.path, 'root');
      final report = await const IsolateGatherService().gather(
        p.absolute(fixtureWow),
        root,
      );
      expect(report.result.characters, 2);
      final again = await const IsolateGatherService().inspect(root);
      expect(again.characters, hasLength(2));
    });

    test('a backup root that cannot be created gives notWritable', () async {
      final blocker = File(p.join(tmp.path, 'file'))..writeAsStringSync('x');
      final report = await gatherInto(fixtureWow, p.join(blocker.path, 'root'));
      expect(report.result.stop!.code, GatherIssueCode.notWritable);
      expect(report.snapshot.characters, isEmpty);
    });

    test('a backup root inside WTF is refused and never created', () async {
      final wow = p.join(tmp.path, 'wow');
      Directory(p.join(wow, 'WTF', 'Account')).createSync(recursive: true);
      final root = p.join(wow, 'WTF', 'WoW Journey');

      final report = await gatherInto(wow, root);

      expect(report.result.stop!.code, GatherIssueCode.overlap);
      expect(Directory(root).existsSync(), isFalse);
      expect(
        Directory(p.join(wow, 'WTF')).listSync().map((e) => p.basename(e.path)),
        ['Account'],
      );
    });

    test('a folder with no WTF/Account gives noWtf', () async {
      final report = await gatherInto(tmp.path, p.join(tmp.path, 'root'));
      expect(report.result.stop!.code, GatherIssueCode.noWtf);
    });
  });

  group('inspectBackupRoot', () {
    late Directory tmp;

    setUp(() => tmp = Directory.systemTemp.createTempSync('wow_journey_snap_'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('a missing root is empty and is not created', () {
      final root = p.join(tmp.path, 'none');
      final snap = inspectBackupRoot(root);
      expect(snap.characters, isEmpty);
      expect(snap.lastGathered, isNull);
      expect(snap.sizeBytes, 0);
      expect(Directory(root).existsSync(), isFalse);
    });

    test('a damaged index gives no characters but the size and the time', () {
      File(p.join(tmp.path, 'latest', 'index.json'))
        ..createSync(recursive: true)
        ..writeAsStringSync('{"characters": [');
      Directory(p.join(tmp.path, 'backups', '20261108T143200Z'))
          .createSync(recursive: true);
      Directory(p.join(tmp.path, 'backups', '20261107T090000Z'))
          .createSync(recursive: true);
      Directory(p.join(tmp.path, 'backups', 'other')).createSync();
      final snap = inspectBackupRoot(tmp.path);
      expect(snap.characters, isEmpty);
      expect(snap.lastGathered, DateTime.utc(2026, 11, 8, 14, 32).toLocal());
      expect(snap.sizeBytes, 16);
    });
  });
}
