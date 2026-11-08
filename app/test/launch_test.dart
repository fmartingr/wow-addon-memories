import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wow_journey/src/platform/single_instance.dart';
import 'package:wow_journey/src/shell/launch.dart';

import 'support/fakes.dart';

class _Built extends StatelessWidget {
  const _Built({required this.startHidden, this.showRequests});

  final bool startHidden;
  final Stream<void>? showRequests;

  @override
  Widget build(BuildContext context) => const SizedBox();
}

Future<Widget?> _launch(
  FakeSingleInstance instance,
  FakeWindow window, [
  List<String> args = const [],
]) => launch(
  args: args,
  instance: instance,
  window: window,
  app: ({required startHidden, showRequests}) =>
      _Built(startHidden: startHidden, showRequests: showRequests),
);

void main() {
  test('the first copy runs the app with its show requests', () async {
    final first = FakeFirstInstance();
    final app = await _launch(FakeSingleInstance(first), FakeWindow(), [
      '--hidden',
    ]);
    final built = app! as _Built;
    expect(built.startHidden, isTrue);
    final shown = <void>[];
    built.showRequests!.listen(shown.add);
    first.requests.add(null);
    await pumpEventQueue();
    expect(shown, hasLength(1));
  });

  test('a start without --hidden is not hidden', () async {
    final app = await _launch(
      FakeSingleInstance(FakeFirstInstance()),
      FakeWindow(),
    );
    expect((app! as _Built).startHidden, isFalse);
  });

  test('a later copy that the first one answered ends', () async {
    final window = FakeWindow();
    final app = await _launch(
      FakeSingleInstance(const OtherInstance(answered: true)),
      window,
      ['--hidden'],
    );
    expect(app, isNull);
    expect(window.calls, isEmpty);
  });

  test('a later copy with no answer shows an error', () async {
    final window = FakeWindow();
    final app = await _launch(
      FakeSingleInstance(const OtherInstance(answered: false)),
      window,
    );
    expect(app, isA<AlreadyRunningApp>());
    expect(window.calls, isEmpty);
  });

  test('a hidden later copy with no answer shows its window', () async {
    final window = FakeWindow();
    await _launch(
      FakeSingleInstance(const OtherInstance(answered: false)),
      window,
      ['--hidden'],
    );
    expect(window.calls, ['show']);
  });

  test('the app runs when the lock cannot be taken', () async {
    final instance = FakeSingleInstance(FakeFirstInstance())
      ..error = const FileSystemExceptionFake();
    final app = await _launch(instance, FakeWindow());
    expect(app, isA<_Built>());
    expect((app! as _Built).showRequests, isNull);
  });

  testWidgets('the error screen says what to do and closes', (tester) async {
    final window = FakeWindow();
    await tester.pumpWidget(AlreadyRunningApp(onClose: window.quit));
    expect(find.text(notAnsweringText), findsOneWidget);
    await tester.tap(find.text('Close'));
    expect(window.calls, ['quit']);
  });
}
