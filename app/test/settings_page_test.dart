import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memories_core/memories_core.dart';
import 'package:wow_journey/src/ui/messages.dart';
import 'package:wow_journey/src/version.dart';

import 'support/fakes.dart';

Future<Fakes> _openSettings(
  WidgetTester tester, {
  FakeFolderPicker? picker,
}) async {
  final fakes = Fakes(
    store: FakeSettingsStore((settings: readySettings, notice: null)),
    discovery: FakeDiscovery(checks: {retailDir: const Valid(retail)}),
    picker: picker,
  );
  await pumpApp(tester, fakes);
  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
  return fakes;
}

Finder _change(String label) => find.bySemanticsLabel(label);

void main() {
  testWidgets('shows the folders, the switches and the version', (
    tester,
  ) async {
    await _openSettings(tester);
    expect(find.text(retailDir), findsOneWidget);
    expect(find.text(readySettings.backupRoot!), findsOneWidget);
    expect(find.text('Watch'), findsOneWidget);
    expect(find.text('Start at login'), findsOneWidget);
    expect(find.textContaining('WoW Journey $appVersion'), findsOneWidget);
  });

  testWidgets('the switches save their value', (tester) async {
    final fakes = await _openSettings(tester);
    await tester.tap(find.text('Watch'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start at login'));
    await tester.pumpAndSettle();
    expect(fakes.store.saved.map((s) => (s.watch, s.startAtLogin)), [
      (false, true),
      (false, false),
    ]);
  });

  testWidgets('the Watch switch stops and starts Watch', (tester) async {
    final fakes = await _openSettings(tester);
    expect(fakes.signature.calls, [retailDir]);
    await tester.pump(const Duration(seconds: 10));
    expect(fakes.signature.calls, hasLength(2));

    await tester.tap(find.text('Watch'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 60));
    expect(fakes.signature.calls, hasLength(2));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(watchingText), findsNothing);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Watch'));
    await tester.pumpAndSettle();
    expect(fakes.signature.calls, hasLength(3));
    await tester.pump(const Duration(seconds: 10));
    expect(fakes.signature.calls, hasLength(4));
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(watchingText), findsOneWidget);
  });

  testWidgets('two toggles before a rebuild keep both changes', (tester) async {
    final fakes = await _openSettings(tester);
    await tester.tap(find.text('Watch'));
    await tester.tap(find.text('Start at login'));
    await tester.pumpAndSettle();
    final last = fakes.store.saved.last;
    expect((last.watch, last.startAtLogin), (false, false));
  });

  testWidgets('a new backup folder warns that the old one stays', (
    tester,
  ) async {
    final fakes = await _openSettings(
      tester,
      picker: FakeFolderPicker(['/new/root']),
    );
    await tester.tap(_change('Change the backup folder'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Your old backup folder stays as it is.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Use this folder'));
    await tester.pumpAndSettle();
    expect(fakes.store.saved.single.backupRoot, '/new/root');
    expect(find.text('/new/root'), findsOneWidget);
  });

  testWidgets('a new backup folder forgets the signature of the old one', (
    tester,
  ) async {
    final fakes = Fakes(
      store: FakeSettingsStore((
        settings: readySettings.copyWith(lastSignature: 'S0'),
        notice: null,
      )),
      discovery: FakeDiscovery(checks: {retailDir: const Valid(retail)}),
      picker: FakeFolderPicker([readySettings.backupRoot, '/new/root']),
    );
    await pumpApp(tester, fakes);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(_change('Change the backup folder'));
    await tester.pumpAndSettle();
    expect(fakes.store.saved.last.lastSignature, 'S0');
    await tester.tap(_change('Change the backup folder'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Use this folder'));
    await tester.pumpAndSettle();
    expect(fakes.store.saved.last.backupRoot, '/new/root');
    expect(fakes.store.saved.last.lastSignature, isNull);
  });

  testWidgets('Cancel in the warning keeps the old backup folder', (
    tester,
  ) async {
    final fakes = await _openSettings(
      tester,
      picker: FakeFolderPicker(['/new/root']),
    );
    await tester.tap(_change('Change the backup folder'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(fakes.store.saved, isEmpty);
  });

  testWidgets('a backup folder inside the WoW folder is refused', (
    tester,
  ) async {
    final fakes = await _openSettings(
      tester,
      picker: FakeFolderPicker([install]),
    );
    await tester.tap(_change('Change the backup folder'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('inside your World of Warcraft folder'),
      findsOneWidget,
    );
    expect(fakes.store.saved, isEmpty);
  });

  testWidgets('an invalid WoW folder shows its message and is not saved', (
    tester,
  ) async {
    final fakes = await _openSettings(
      tester,
      picker: FakeFolderPicker(['/tmp/empty']),
    );
    await tester.tap(_change('Change the WoW folder'));
    await tester.pumpAndSettle();
    expect(find.text(const NoWtf('/tmp/empty').message), findsOneWidget);
    expect(fakes.store.saved, isEmpty);
  });

  testWidgets('an install folder asks for one game version', (tester) async {
    final fakes = await _openSettings(
      tester,
      picker: FakeFolderPicker([install]),
    );
    fakes.discovery.checks[install] = const IsInstallFolder(install, [
      retail,
      forever,
    ]);
    await tester.tap(_change('Change the WoW folder'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a game version'), findsOneWidget);
    await tester.tap(find.text('_forever_'));
    await tester.pumpAndSettle();
    expect(fakes.store.saved.single.flavorDir, foreverDir);
  });

  testWidgets('a cancelled WoW folder pick saves nothing', (tester) async {
    final fakes = await _openSettings(tester, picker: FakeFolderPicker([null]));
    await tester.tap(_change('Change the WoW folder'));
    await tester.pumpAndSettle();
    expect(fakes.picker.calls, 1);
    expect(fakes.store.saved, isEmpty);
  });
}
