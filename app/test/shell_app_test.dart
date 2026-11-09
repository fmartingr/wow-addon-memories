import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memories_core/memories_core.dart';
import 'package:wow_journey/src/shell/shell_controller.dart';
import 'package:wow_journey/src/ui/messages.dart';

import 'support/fakes.dart';

Fakes _ready({bool startAtLogin = true}) => Fakes(
  store: FakeSettingsStore((
    settings: readySettings.copyWith(startAtLogin: startAtLogin),
    notice: null,
  )),
  discovery: FakeDiscovery(checks: {retailDir: const Valid(retail)}),
);

Future<void> _walkWizard(
  WidgetTester tester, {
  bool startAtLogin = true,
}) async {
  for (var step = 0; step < 2; step++) {
    await tester.tap(find.widgetWithText(FilledButton, 'Next'));
    await tester.pumpAndSettle();
  }
  if (!startAtLogin) {
    await tester.tap(find.text('Start at login'));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.widgetWithText(FilledButton, 'Finish'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the app starts the tray and takes over the close button', (
    tester,
  ) async {
    final fakes = _ready();
    await pumpApp(tester, fakes);
    expect(fakes.window.calls, ['init']);
    expect(fakes.tray.items.map((i) => i.label), [
      TrayLabels.gatherNow,
      TrayLabels.openWindow,
      TrayLabels.openBackupFolder,
      TrayLabels.quit,
    ]);
  });

  testWidgets('Quit from the tray stops Watch and quits', (tester) async {
    final fakes = _ready();
    await pumpApp(tester, fakes);
    expect(find.text(watchingText), findsOneWidget);
    expect(fakes.signature.calls, hasLength(1));

    fakes.tray.select(TrayLabels.quit);
    await tester.pumpAndSettle();
    expect(find.text(watchingText), findsNothing);
    expect(fakes.tray.disposed, isTrue);
    expect(fakes.window.calls.last, 'quit');
    await tester.pump(const Duration(seconds: 60));
    expect(fakes.signature.calls, hasLength(1));
  });

  testWidgets('Gather now from the tray gathers', (tester) async {
    final fakes = _ready();
    await pumpApp(tester, fakes);
    fakes.tray.select(TrayLabels.gatherNow);
    await tester.pumpAndSettle();
    expect(fakes.gather.calls, [(retailDir, readySettings.backupRoot!)]);
    expect(find.textContaining('Up to date'), findsOneWidget);
  });

  testWidgets('a later start shows the window', (tester) async {
    final fakes = _ready();
    final requests = StreamController<void>.broadcast();
    addTearDown(requests.close);
    await pumpApp(tester, fakes, showRequests: requests.stream);
    requests.add(null);
    await tester.pumpAndSettle();
    expect(fakes.window.calls, ['init', 'show']);
  });

  testWidgets('a later start during the wizard shows it', (tester) async {
    final fakes = Fakes(discovery: FakeDiscovery(found: [retail]));
    final requests = StreamController<void>.broadcast();
    addTearDown(requests.close);
    await pumpApp(tester, fakes, showRequests: requests.stream);
    requests.add(null);
    await tester.pumpAndSettle();
    expect(fakes.window.calls, ['init', 'show']);
    expect(find.text('Step 1 of 3'), findsOneWidget);
  });

  group('the login entry', () {
    testWidgets('is written again at a start with the switch on', (
      tester,
    ) async {
      final fakes = _ready();
      await pumpApp(tester, fakes);
      expect(fakes.startup.applied, [true]);
    });

    testWidgets('is not written at a start with the switch off', (
      tester,
    ) async {
      final fakes = _ready(startAtLogin: false);
      await pumpApp(tester, fakes);
      expect(fakes.startup.applied, isEmpty);
    });

    testWidgets('is written on Finish', (tester) async {
      final fakes = Fakes(discovery: FakeDiscovery(found: [retail]));
      await pumpApp(tester, fakes);
      expect(fakes.startup.applied, isEmpty);
      await _walkWizard(tester);
      expect(fakes.startup.applied, [true]);
    });

    testWidgets('is removed on Finish with the switch off', (tester) async {
      final fakes = Fakes(discovery: FakeDiscovery(found: [retail]));
      await pumpApp(tester, fakes);
      await _walkWizard(tester, startAtLogin: false);
      expect(fakes.startup.applied, [false]);
    });

    testWidgets('follows the settings switch', (tester) async {
      final fakes = _ready();
      await pumpApp(tester, fakes);
      await openTab(tester, 'Settings');
      await tester.tap(find.text('Start at login'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Start at login'));
      await tester.pumpAndSettle();
      expect(fakes.startup.applied, [true, false, true]);
    });
  });

  group('a hidden start', () {
    testWidgets('keeps the window hidden', (tester) async {
      final fakes = _ready();
      await pumpApp(tester, fakes, startHidden: true);
      expect(fakes.window.calls, ['init']);
    });

    testWidgets('shows the wizard on a first start', (tester) async {
      final fakes = Fakes(discovery: FakeDiscovery(found: [retail]));
      await pumpApp(tester, fakes, startHidden: true);
      expect(fakes.window.calls, ['init', 'show']);
    });
  });
}
