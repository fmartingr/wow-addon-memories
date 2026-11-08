import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memories_core/memories_core.dart';
import 'package:wow_journey/src/settings/settings.dart';
import 'package:wow_journey/src/settings/settings_store.dart';

import 'support/fakes.dart';

Finder _next() => find.widgetWithText(FilledButton, 'Next');
Finder _finish() => find.widgetWithText(FilledButton, 'Finish');

bool _enabled(WidgetTester tester, Finder button) =>
    tester.widget<ButtonStyleButton>(button).onPressed != null;

void main() {
  testWidgets('happy path: the found folder, the default backup, both '
      'switches on, then the main screen', (tester) async {
    final fakes = Fakes(discovery: FakeDiscovery(found: [retail]));
    await pumpApp(tester, fakes);

    expect(find.text('Step 1 of 3'), findsOneWidget);
    expect(find.textContaining(retailDir), findsOneWidget);
    expect(fakes.picker.calls, 0);
    await tester.tap(_next());
    await tester.pumpAndSettle();

    expect(find.text('Step 2 of 3'), findsOneWidget);
    expect(find.text(defaultRoot), findsOneWidget);
    expect(
      find.text('We keep a copy of your game files and your screenshots here.'),
      findsOneWidget,
    );
    await tester.tap(_next());
    await tester.pumpAndSettle();

    expect(find.text('Step 3 of 3'), findsOneWidget);
    final switches = tester.widgetList<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    expect(switches.map((s) => s.value), [true, true]);
    await tester.tap(_finish());
    await tester.pumpAndSettle();

    expect(fakes.store.saved, [
      const Settings(
        flavorDir: retailDir,
        backupRoot: defaultRoot,
        wizardDone: true,
      ),
    ]);
    expect(find.text('Gather now'), findsOneWidget);
    expect(find.text('Step 1 of 3'), findsNothing);
  });

  testWidgets('Back returns to the step before', (tester) async {
    await pumpApp(tester, Fakes(discovery: FakeDiscovery(found: [retail])));
    await tester.tap(_next());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Back'));
    await tester.pumpAndSettle();
    expect(find.text('Step 1 of 3'), findsOneWidget);
  });

  testWidgets('the switches can be turned off before Finish', (tester) async {
    final fakes = Fakes(discovery: FakeDiscovery(found: [retail]));
    await pumpApp(tester, fakes);
    await tester.tap(_next());
    await tester.pumpAndSettle();
    await tester.tap(_next());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Watch'));
    await tester.tap(find.text('Start at login'));
    await tester.pumpAndSettle();
    await tester.tap(_finish());
    await tester.pumpAndSettle();
    expect(fakes.store.saved.single.watch, isFalse);
    expect(fakes.store.saved.single.startAtLogin, isFalse);
  });

  testWidgets('no folder found opens the picker; a cancel shows the text and '
      'Choose folder', (tester) async {
    final fakes = Fakes(picker: FakeFolderPicker([null]));
    await pumpApp(tester, fakes);

    expect(fakes.picker.calls, 1);
    expect(
      find.textContaining('We could not find World of Warcraft'),
      findsOneWidget,
    );
    expect(find.text('Choose folder'), findsOneWidget);
    expect(_enabled(tester, _next()), isFalse);
    expect(fakes.store.saved, isEmpty);
  });

  testWidgets('no folder found, then a valid pick', (tester) async {
    final fakes = Fakes(
      discovery: FakeDiscovery(checks: {foreverDir: const Valid(forever)}),
      picker: FakeFolderPicker([foreverDir]),
    );
    await pumpApp(tester, fakes);

    expect(fakes.discovery.validated, [foreverDir]);
    expect(find.textContaining(foreverDir), findsOneWidget);
    expect(find.textContaining('No Memories data yet.'), findsOneWidget);
    expect(_enabled(tester, _next()), isTrue);
  });

  testWidgets('an invalid pick shows the message and is not used', (
    tester,
  ) async {
    final fakes = Fakes(
      discovery: FakeDiscovery(found: [retail]),
      picker: FakeFolderPicker(['/home/player/Pictures']),
    );
    await pumpApp(tester, fakes);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Change'));
    await tester.pumpAndSettle();

    expect(
      find.text(const NoWtf('/home/player/Pictures').message),
      findsOneWidget,
    );
    expect(find.textContaining(retailDir), findsOneWidget);
    expect(find.textContaining('Pictures'), findsNothing);

    await tester.tap(_next());
    await tester.pumpAndSettle();
    await tester.tap(_next());
    await tester.pumpAndSettle();
    await tester.tap(_finish());
    await tester.pumpAndSettle();
    expect(fakes.store.saved.single.flavorDir, retailDir);
  });

  testWidgets('a cancelled Change keeps the found folder', (tester) async {
    final fakes = Fakes(
      discovery: FakeDiscovery(found: [retail]),
      picker: FakeFolderPicker([null]),
    );
    await pumpApp(tester, fakes);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Change'));
    await tester.pumpAndSettle();
    expect(fakes.picker.calls, 1);
    expect(find.textContaining(retailDir), findsOneWidget);
    expect(_enabled(tester, _next()), isTrue);
  });

  testWidgets('two flavors show a list; the first is chosen', (tester) async {
    final fakes = Fakes(discovery: FakeDiscovery(found: [retail, forever]));
    await pumpApp(tester, fakes);

    expect(find.byType(RadioListTile<WowFolder>), findsNWidgets(2));
    await tester.tap(find.text('_forever_'));
    await tester.pumpAndSettle();
    await tester.tap(_next());
    await tester.pumpAndSettle();
    await tester.tap(_next());
    await tester.pumpAndSettle();
    await tester.tap(_finish());
    await tester.pumpAndSettle();
    expect(fakes.store.saved.single.flavorDir, foreverDir);
  });

  testWidgets('a picked install folder lists its game versions', (
    tester,
  ) async {
    final fakes = Fakes(
      discovery: FakeDiscovery(
        checks: {
          install: const IsInstallFolder(install, [retail, forever]),
        },
      ),
      picker: FakeFolderPicker([install]),
    );
    await pumpApp(tester, fakes);

    expect(find.byType(RadioListTile<WowFolder>), findsNWidgets(2));
    expect(
      find.text(const IsInstallFolder(install, [retail, forever]).message),
      findsOneWidget,
    );
    expect(_enabled(tester, _next()), isTrue);
  });

  testWidgets('step 2 Change uses the picked backup folder', (tester) async {
    final fakes = Fakes(
      discovery: FakeDiscovery(found: [retail]),
      picker: FakeFolderPicker(['/data/journey']),
    );
    await pumpApp(tester, fakes);
    await tester.tap(_next());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Change'));
    await tester.pumpAndSettle();
    expect(find.text('/data/journey'), findsOneWidget);
    await tester.tap(_next());
    await tester.pumpAndSettle();
    await tester.tap(_finish());
    await tester.pumpAndSettle();
    expect(fakes.store.saved.single.backupRoot, '/data/journey');
  });

  testWidgets('a backup folder inside the WoW folder is refused', (
    tester,
  ) async {
    final fakes = Fakes(
      discovery: FakeDiscovery(found: [retail]),
      picker: FakeFolderPicker(['$install/backups']),
    );
    await pumpApp(tester, fakes);
    await tester.tap(_next());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Change'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('inside your World of Warcraft folder'),
      findsOneWidget,
    );
    expect(find.text(defaultRoot), findsOneWidget);
  });

  testWidgets('a damaged settings file shows its notice in the wizard', (
    tester,
  ) async {
    final fakes = Fakes(
      store: FakeSettingsStore((
        settings: const Settings(),
        notice: damagedSettingsNotice,
      )),
      discovery: FakeDiscovery(found: [retail]),
    );
    await pumpApp(tester, fakes);
    expect(find.text(damagedSettingsNotice), findsOneWidget);
  });

  testWidgets('saved settings skip the wizard', (tester) async {
    final fakes = Fakes(
      store: FakeSettingsStore((settings: readySettings, notice: null)),
    );
    await pumpApp(tester, fakes);
    expect(find.text('Step 1 of 3'), findsNothing);
    expect(find.text('Gather now'), findsOneWidget);
    expect(fakes.discovery.discoverCalls, 0);
  });
}
