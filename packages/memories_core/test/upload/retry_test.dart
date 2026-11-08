import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:memories_core/memories_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fixture.dart';
import 'fake_site.dart';
import 'fake_time.dart';

const String _brumamar = 'wow/eu/brumamar/nandu';
const String _shot =
    'PUT /api/v1/characters/$_brumamar/screenshots/'
    'WoWScrnShot_110126_114820.jpg';

void main() {
  late FakeSite site;
  late FakeTime time;
  late UploadKey key;
  final waits = <int>[];

  UploadClient make({
    int? perMinute = 0,
    Duration budget = defaultRetryBudget,
    http.Client? http,
  }) => UploadClient(
    site.uri,
    key,
    client: http,
    requestsPerMinute: perMinute,
    retryBudget: budget,
    sleep: time.sleep,
    monotonic: time.monotonic,
    onWait: waits.add,
  );

  setUp(() async {
    site = await FakeSite.start();
    time = FakeTime();
    key = UploadKey.generate();
    waits.clear();
  });
  tearDown(() => site.close());

  group('retry', () {
    test('a 429 waits Retry-After, signs again and then succeeds', () async {
      final client = make();
      addTearDown(client.close);
      await client.register();
      site.rateLimit('GET /api/v1/me', 2, seconds: 7);
      final me = await client.me();
      expect(me.screenshots, 'none');
      final tries = site.callsTo('GET /api/v1/me');
      expect(tries, hasLength(3));
      expect(
        tries.map((c) => c.headers['memories-nonce']).toSet(),
        hasLength(3),
      );
      expect(waits, [7, 7]);
      for (final s in time.sleeps) {
        expect(s, greaterThanOrEqualTo(const Duration(seconds: 7)));
        expect(s, lessThan(const Duration(seconds: 8)));
      }
    });

    test(
      'no Retry-After waits 5 seconds and a long one is cut to 70',
      () async {
        final client = make();
        addTearDown(client.close);
        await client.register();
        site.rateLimit('GET /api/v1/me', 1);
        await client.me();
        site.rateLimit('GET /api/v1/me', 1, seconds: 3600);
        await client.me();
        expect(waits, [5, 70]);
      },
    );

    test('a 503 is waited out too', () async {
      final client = make();
      addTearDown(client.close);
      await client.register();
      site.failTimes('GET /api/v1/me', 1, Reply.error(503, 'busy', 'Busy.'));
      await client.me();
      expect(waits, [5]);
    });

    test('the budget spent gives a recoverable error', () async {
      final client = make(budget: const Duration(seconds: 25));
      addTearDown(client.close);
      await client.register();
      site.rateLimit('GET /api/v1/me', 100, seconds: 10);
      await expectLater(
        client.me(),
        throwsA(
          isA<UploadException>()
              .having((e) => e.status, 'status', 429)
              .having((e) => e.recoverable, 'recoverable', isTrue)
              .having((e) => e.retryAfter, 'retryAfter', 10),
        ),
      );
      expect(site.callsTo('GET /api/v1/me'), hasLength(3));
      expect(time.slept, lessThanOrEqualTo(const Duration(seconds: 25)));
    });

    test('other errors are not retried and are not recoverable', () async {
      final client = make();
      addTearDown(client.close);
      for (final (status, code) in [
        (401, 'bad_signature'),
        (403, 'invite_invalid'),
        (409, 'claimed'),
        (422, 'invalid'),
      ]) {
        site.overrides['GET /api/v1/me'] = Reply.error(status, code, 'No.');
        await expectLater(
          client.me(),
          throwsA(
            isA<UploadException>()
                .having((e) => e.code, 'code', code)
                .having((e) => e.recoverable, 'recoverable', isFalse),
          ),
        );
      }
      expect(site.callsTo('GET /api/v1/me'), hasLength(4));
      expect(time.sleeps, isEmpty);
    });

    test('a network error is tried 3 times with a growing pause', () async {
      var calls = 0;
      final flaky = MockClient((request) async {
        calls++;
        if (calls < 3) throw http.ClientException('reset');
        return http.Response('{"screenshots":"none","characters":[]}', 200);
      });
      final client = make(http: flaky);
      expect((await client.me()).screenshots, 'none');
      expect(calls, 3);
      expect(time.sleeps, hasLength(2));
      expect(time.sleeps[0], lessThan(const Duration(seconds: 2)));
      expect(time.sleeps[1], greaterThanOrEqualTo(const Duration(seconds: 2)));
      expect(waits, isEmpty, reason: 'a blip is not announced');
    });

    test('a network error after 3 tries is the network error', () async {
      var calls = 0;
      final dead = MockClient((request) async {
        calls++;
        throw http.ClientException('down');
      });
      final client = make(http: dead);
      await expectLater(
        client.me(),
        throwsA(
          isA<UploadException>()
              .having((e) => e.code, 'code', 'network')
              .having((e) => e.recoverable, 'recoverable', isFalse),
        ),
      );
      expect(calls, 3);
    });
  });

  group('pacing', () {
    test('no more than the limit goes out in any minute', () async {
      final client = make(perMinute: 10);
      addTearDown(client.close);
      await client.register();
      final starts = <Duration>[];
      for (var i = 0; i < 24; i++) {
        await client.me();
        starts.add(time.now);
      }
      expect(time.sleeps, [
        const Duration(minutes: 1),
        const Duration(minutes: 1),
      ]);
      // register and the 24 calls of me are 25 requests.
      expect(site.calls, hasLength(25));
      for (var i = 10; i < starts.length; i++) {
        expect(
          starts[i] - starts[i - 10],
          greaterThanOrEqualTo(const Duration(minutes: 1)),
        );
      }
    });

    test('0 and null turn it off', () async {
      for (final limit in [0, null]) {
        final client = make(perMinute: limit);
        for (var i = 0; i < 30; i++) {
          await client.info();
        }
        client.close();
      }
      expect(time.sleeps, isEmpty);
    });

    test('a retried request counts against the limit', () async {
      final client = make(perMinute: 3);
      addTearDown(client.close);
      await client.register();
      site.rateLimit('GET /api/v1/me', 1, seconds: 1);
      await client.me();
      await client.me();
      expect(time.sleeps.any((d) => d >= const Duration(seconds: 50)), isTrue);
    });
  });

  group('syncLatest', () {
    late Directory tmp;
    late Directory latest;
    late UploadState state;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('memories-retry-');
      latest = Directory(p.join(tmp.path, 'latest'));
      copyTree(expectedDir, latest.path);
      state = UploadState.empty();
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    Future<UploadClient> registered({
      Duration budget = defaultRetryBudget,
    }) async {
      final client = make(budget: budget);
      addTearDown(client.close);
      await client.register();
      return client;
    }

    test('a rate limit that lifts is invisible', () async {
      final client = await registered();
      site.screenshots = 'approved';
      site.rateLimit('POST /api/v1/characters', 2, seconds: 3);
      site.rateLimit(_shot, 1, seconds: 3);
      final r = await syncLatest(latest, client, state);
      expect(r.paused, isFalse);
      expect(r.failed, isFalse);
      expect(
        r.characters.map((c) => c.status),
        everyElement(SyncStatus.uploaded),
      );
      expect(r.characters.first.shots.uploaded, 2);
      expect(waits, [3, 3, 3]);
    });

    test(
      'a spent budget pauses the run, and the next run resumes it',
      () async {
        final client = await registered(budget: const Duration(seconds: 12));
        site.screenshots = 'approved';
        site.rateLimit(_shot, 1000, seconds: 5);
        final paused = await syncLatest(latest, client, state);
        expect(paused.paused, isTrue);
        expect(paused.failed, isFalse);
        final first = paused.characters.first;
        expect(first.status, SyncStatus.uploaded);
        expect(first.shots.errors, isEmpty);
        expect(first.shots.stop!.recoverable, isTrue);
        expect(paused.characters.last.status, SyncStatus.failed);
        expect(paused.characters.last.error!.recoverable, isTrue);
        expect(site.callsTo('POST /api/v1/characters'), hasLength(1));

        site.failTimes(_shot, 0, const Reply(200));
        final next = await syncLatest(
          latest,
          make(budget: const Duration(seconds: 12)),
          state,
        );
        expect(next.paused, isFalse);
        expect(next.failed, isFalse);
        expect(next.characters.first.status, SyncStatus.unchanged);
        expect(next.characters.first.shots.uploaded, 2);
        expect(next.characters.last.status, SyncStatus.uploaded);
        expect(site.callsTo('POST /api/v1/characters'), hasLength(2));
      },
    );

    test('a spent budget on me() throws a recoverable error', () async {
      final client = await registered(budget: const Duration(seconds: 6));
      site.rateLimit('GET /api/v1/me', 100, seconds: 5);
      await expectLater(
        syncLatest(latest, client, state),
        throwsA(
          isA<UploadException>().having((e) => e.recoverable, 'r', isTrue),
        ),
      );
    });

    test(
      'onProgress counts the characters and the screenshots to send',
      () async {
        final client = await registered();
        site.screenshots = 'approved';
        final seen = <(int, int)>[];
        await syncLatest(
          latest,
          client,
          state,
          onProgress: (done, total) => seen.add((done, total)),
        );
        expect(seen, [(0, 4), (1, 4), (2, 4), (3, 4), (4, 4)]);

        seen.clear();
        await syncLatest(
          latest,
          client,
          state,
          onProgress: (done, total) => seen.add((done, total)),
        );
        expect(seen, [(0, 0)]);
      },
    );

    test('onProgress ticks for a failed character too', () async {
      final client = await registered(budget: Duration.zero);
      site.overrides['POST /api/v1/characters'] = Reply.error(
        422,
        'invalid',
        'No.',
      );
      final seen = <(int, int)>[];
      await syncLatest(
        latest,
        client,
        state,
        onProgress: (done, total) => seen.add((done, total)),
      );
      expect(seen, [(0, 2), (1, 2), (2, 2)]);
    });
  });
}
