import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wow_journey/src/platform/single_instance.dart';

void main() {
  late Directory dir;
  final firsts = <FirstInstance>[];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wow_journey_instance_');
  });

  tearDown(() async {
    for (final f in firsts) {
      await f.release();
    }
    firsts.clear();
    dir.deleteSync(recursive: true);
  });

  FileSingleInstance instance({
    Duration timeout = const Duration(seconds: 2),
  }) => FileSingleInstance(() async => dir.path, timeout: timeout);

  File lockFile() => File(p.join(dir.path, 'instance.lock'));

  test('the first claim gets the lock and writes a loopback port', () async {
    firsts.add(await instance().claim() as FirstInstance);
    final text = lockFile().readAsStringSync();
    expect(text, matches(RegExp(r'^\d+ [0-9a-f]{32}\n$')));
  });

  test('a second lock object on the file asks the first to show its '
      'window', () async {
    final one = await instance().claim() as FirstInstance;
    firsts.add(one);
    final shown = <void>[];
    one.showRequests.listen(shown.add);

    final two = await instance().claim();
    expect(two, isA<OtherInstance>());
    expect((two as OtherInstance).answered, isTrue);
    await pumpEventQueue();
    expect(shown, hasLength(1));
  });

  test('after a release the next claim is the first again', () async {
    final one = await instance().claim() as FirstInstance;
    await one.release();
    final two = await instance().claim();
    expect(two, isA<FirstInstance>());
    firsts.add(two as FirstInstance);
  });

  test('a lock file left by a copy that ended is taken over', () async {
    lockFile().writeAsStringSync('51234 ${'a' * 32}\n');
    final claim = await instance().claim();
    expect(claim, isA<FirstInstance>());
    firsts.add(claim as FirstInstance);
    expect(lockFile().readAsStringSync(), isNot(contains('51234 ')));
  });

  test('a first copy that does not answer in time is reported', () async {
    firsts.add(await instance().claim() as FirstInstance);
    final silent = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(silent.close);
    final held = <Socket>[];
    silent.listen(held.add);
    addTearDown(() {
      for (final s in held) {
        s.destroy();
      }
    });
    lockFile().writeAsStringSync('${silent.port} ${'b' * 32}\n');

    final watch = Stopwatch()..start();
    final claim = await instance(timeout: const Duration(milliseconds: 300))
        .claim();
    expect(claim, isA<OtherInstance>());
    expect((claim as OtherInstance).answered, isFalse);
    expect(watch.elapsed, lessThan(const Duration(seconds: 2)));
  });

  test('a lock file with no port yet is reported after the timeout', () async {
    firsts.add(await instance().claim() as FirstInstance);
    lockFile().writeAsStringSync('');
    final claim = await instance(timeout: const Duration(milliseconds: 300))
        .claim();
    expect((claim as OtherInstance).answered, isFalse);
  });

  test('a wrong token or any other message shows nothing', () async {
    final one = await instance().claim() as FirstInstance;
    firsts.add(one);
    final shown = <void>[];
    one.showRequests.listen(shown.add);
    final port = int.parse(lockFile().readAsStringSync().split(' ').first);

    for (final message in ['show ${'0' * 32}\n', 'quit\n', '${'x' * 1000}\n']) {
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, port);
      socket.write(message);
      await socket.flush();
      final reply = await FileSingleInstance.readLine(
        socket,
        const Duration(seconds: 2),
      );
      socket.destroy();
      expect(reply, isNull, reason: message);
    }
    expect(shown, isEmpty);
  });
}
