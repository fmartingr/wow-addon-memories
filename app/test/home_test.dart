import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memories_core/memories_core.dart';
import 'package:path/path.dart' as p;
import 'package:wow_journey/src/settings/settings_store.dart';
import 'package:wow_journey/src/gather/gather_controller.dart';
import 'package:wow_journey/src/settings/settings.dart';
import 'package:wow_journey/src/ui/messages.dart';

import 'support/fakes.dart';
import 'support/texts.dart';

const String root = '/backups/WoW Journey';

Fakes _ready({FakeGatherService? gather, FakeFolderPicker? picker}) => Fakes(
  store: FakeSettingsStore((settings: readySettings, notice: null)),
  discovery: FakeDiscovery(checks: {retailDir: const Valid(retail)}),
  gather: gather,
  picker: picker,
);

Finder _gatherButton() => find.ancestor(
  of: find.byIcon(Icons.sync),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

bool _enabled(WidgetTester tester, Finder button) =>
    tester.widget<ButtonStyleButton>(button).onPressed != null;

GatherReport _report(List<GatherIssue> issues, {int characters = 0}) => (
  result: GatherResult(characters: characters, issues: issues),
  snapshot: const BackupSnapshot(),
);

void main() {
  testWidgets('never gathered: status, hint, empty counts and the size', (
    tester,
  ) async {
    final fakes = _ready();
    await pumpApp(tester, fakes);

    expect(find.text('Never gathered'), findsOneWidget);
    expect(find.text(saveHintText), findsOneWidget);
    expect(find.text('No characters yet. Click Gather now.'), findsOneWidget);
    expect(find.text('Size: 0 bytes'), findsOneWidget);
    expect(find.text(root), findsOneWidget);
    expect(_enabled(tester, _gatherButton()), isTrue);
    expect(fakes.gather.inspected, [root]);
    expect(find.text(wowFolderGoneText), findsNothing);
  });

  testWidgets('Watch on: the status line shows and a change gathers once', (
    tester,
  ) async {
    final fakes = _ready();
    fakes.store.loaded = (
      settings: readySettings.copyWith(lastSignature: 'S0'),
      notice: null,
    );
    fakes.signature.value = 'S1';
    fakes.clock = tester.binding.clock.now;
    await pumpApp(tester, fakes);
    expect(find.text(watchingText), findsOneWidget);
    expect(fakes.gather.calls, isEmpty);
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(fakes.gather.calls, [(retailDir, root)]);
    expect(fakes.store.saved.last.lastSignature, 'S1');
    await tester.pump(const Duration(seconds: 60));
    expect(fakes.gather.calls, hasLength(1));
  });

  testWidgets('Watch off: no status line and no poll', (tester) async {
    final fakes = _ready();
    fakes.store.loaded = (
      settings: readySettings.copyWith(watch: false),
      notice: null,
    );
    await pumpApp(tester, fakes);
    await tester.pump(const Duration(seconds: 30));
    expect(find.text(watchingText), findsNothing);
    expect(fakes.signature.calls, isEmpty);
  });

  testWidgets('the earlier data shows the characters, counts and time', (
    tester,
  ) async {
    final last = DateTime.now().subtract(const Duration(days: 3));
    final fakes = _ready(
      gather: FakeGatherService(
        snapshot: BackupSnapshot(
          characters: const [
            CharacterSummary(
              id: 'eu-brumamar-nandu',
              name: 'Ñandú',
              realm: 'Brumamar',
              level: 10,
              className: 'HUNTER',
            ),
          ],
          lines: 15,
          screenshots: 2,
          lastGathered: last,
          sizeBytes: 3 * 1024 * 1024,
        ),
      ),
    );
    await pumpApp(tester, fakes);

    expect(find.text('Ñandú'), findsOneWidget);
    expect(find.text('Brumamar · Level 10 · Hunter'), findsOneWidget);
    expect(find.bySemanticsLabel('Characters: 1'), findsOneWidget);
    expect(find.bySemanticsLabel('Journal lines: 15'), findsOneWidget);
    expect(find.bySemanticsLabel('Screenshots: 2'), findsOneWidget);
    expect(find.text('Size: 3.0 MB'), findsOneWidget);
    expect(find.textContaining('Last gathered'), findsOneWidget);
  });

  testWidgets('running: the button is off and shows progress; done after', (
    tester,
  ) async {
    final service = FakeGatherService()..pending = Completer<GatherReport>();
    final fakes = _ready(gather: service);
    await pumpApp(tester, fakes);

    await tester.tap(_gatherButton());
    await tester.pump();

    expect(service.calls, [(retailDir, root)]);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Gathering your journey…'), findsOneWidget);
    expect(_enabled(tester, _gatherButton()), isFalse);
    await tester.tap(_gatherButton(), warnIfMissed: false);
    await tester.pump();
    expect(service.calls, hasLength(1));

    // This gather wrote one character; index.json also keeps an earlier one.
    service.pending!.complete((
      result: const GatherResult(characters: 1, lines: 10, screenshots: 1),
      snapshot: const BackupSnapshot(
        characters: [
          CharacterSummary(id: 'eu-a-a', name: 'A', realm: 'R'),
          CharacterSummary(id: 'eu-a-b', name: 'B', realm: 'R'),
        ],
        lines: 16,
        screenshots: 2,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(find.textContaining('Up to date. Last gathered'), findsOneWidget);
    expect(find.bySemanticsLabel('Characters: 2'), findsOneWidget);
    expect(find.bySemanticsLabel('Journal lines: 16'), findsOneWidget);
    expect(_enabled(tester, _gatherButton()), isTrue);
  });

  testWidgets('done with issues shows each problem once with its fix', (
    tester,
  ) async {
    final service = FakeGatherService()
      ..next = _report(characters: 1, [
        issue(GatherIssueCode.damagedFile, path: '/wtf/a.lua'),
        issue(GatherIssueCode.damagedFile, path: '/wtf/b.lua'),
        issue(GatherIssueCode.duplicateGuid),
      ]);
    await pumpApp(tester, _ready(gather: service));
    await tester.tap(_gatherButton());
    await tester.pumpAndSettle();

    expect(find.textContaining('Gathered with problems.'), findsOneWidget);
    expect(
      find.text(issueText(en, GatherIssueCode.damagedFile)),
      findsOneWidget,
    );
    expect(find.text('/wtf/a.lua'), findsOneWidget);
    expect(find.text('/wtf/b.lua'), findsOneWidget);
    expect(
      find.text(issueText(en, GatherIssueCode.duplicateGuid)),
      findsOneWidget,
    );
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('core text'), findsNothing);

    await tapVisible(tester, find.text('Try again'));
    await tester.pumpAndSettle();
    expect(service.calls, hasLength(2));
  });

  testWidgets('failed: no data tells the player what to do', (tester) async {
    final service = FakeGatherService()
      ..next = _report([
        issue(GatherIssueCode.noData, path: retailDir, fatal: true),
      ]);
    await pumpApp(tester, _ready(gather: service));
    await tester.tap(_gatherButton());
    await tester.pumpAndSettle();

    expect(
      find.text('The last gather did not finish. See the problem below.'),
      findsOneWidget,
    );
    expect(find.text(noDataText), findsOneWidget);
  });

  testWidgets('an error of the gather shows plain text, no stack trace', (
    tester,
  ) async {
    final service = FakeGatherService()..error = StateError('boom at line 3');
    await pumpApp(tester, _ready(gather: service));
    await tester.tap(_gatherButton());
    await tester.pumpAndSettle();

    expect(find.text(issueText(en, GatherIssueCode.ioError)), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);
  });

  testWidgets('every issue code shows its text on the screen', (tester) async {
    useWindow(tester, height: 8000);
    final service = FakeGatherService()
      ..next = _report([for (final c in GatherIssueCode.values) issue(c)]);
    await pumpApp(tester, _ready(gather: service));
    await tester.tap(_gatherButton());
    await tester.pumpAndSettle();

    for (final c in GatherIssueCode.values) {
      expect(find.text(issueText(en, c), skipOffstage: false), findsOneWidget);
    }
  });

  testWidgets('a noWtf fix opens the picker and saves a valid folder', (
    tester,
  ) async {
    final service = FakeGatherService()
      ..next = _report([issue(GatherIssueCode.noWtf, fatal: true)]);
    final fakes = _ready(
      gather: service,
      picker: FakeFolderPicker([foreverDir]),
    );
    fakes.discovery.checks[foreverDir] = const Valid(forever);
    await pumpApp(tester, fakes);
    await tester.tap(_gatherButton());
    await tester.pumpAndSettle();

    await tapVisible(tester, find.text('Choose folder'));
    await tester.pumpAndSettle();
    expect(fakes.store.saved.single.flavorDir, foreverDir);
  });

  testWidgets('a notWritable fix asks for a backup folder and warns', (
    tester,
  ) async {
    final service = FakeGatherService()
      ..next = _report([issue(GatherIssueCode.notWritable, fatal: true)]);
    final fakes = _ready(
      gather: service,
      picker: FakeFolderPicker(['/other/root']),
    );
    await pumpApp(tester, fakes);
    await tester.tap(_gatherButton());
    await tester.pumpAndSettle();

    await tapVisible(tester, find.text('Choose backup folder'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Your old backup folder stays as it is.'),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Use this folder'));
    await tester.pumpAndSettle();
    expect(fakes.store.saved.single.backupRoot, '/other/root');
    expect(fakes.gather.inspected.last, '/other/root');
  });

  testWidgets('a WoW folder that is gone shows the Choose folder fix', (
    tester,
  ) async {
    final fakes = Fakes(
      store: FakeSettingsStore((settings: readySettings, notice: null)),
    );
    await pumpApp(tester, fakes);
    expect(find.text(wowFolderGoneText), findsOneWidget);
    expect(find.text('Choose folder'), findsOneWidget);
  });

  testWidgets('a picker cancel on the fix keeps the settings', (tester) async {
    final fakes = Fakes(
      store: FakeSettingsStore((settings: readySettings, notice: null)),
      picker: FakeFolderPicker([null]),
    );
    await pumpApp(tester, fakes);
    await tapVisible(tester, find.text('Choose folder'));
    await tester.pumpAndSettle();
    expect(fakes.picker.calls, 1);
    expect(fakes.store.saved, isEmpty);
  });

  testWidgets('the open buttons open the backup root and latest', (
    tester,
  ) async {
    final fakes = _ready();
    await pumpApp(tester, fakes);
    await tapVisible(tester, find.text('Open backup folder'));
    await tapVisible(tester, find.text('Open latest data'));
    await tester.pumpAndSettle();
    expect(fakes.opener.opened, [root, p.join(root, 'latest')]);
  });

  testWidgets('a folder that cannot be opened shows a message', (tester) async {
    final fakes = _ready()..opener.result = false;
    await pumpApp(tester, fakes);
    await tapVisible(tester, find.text('Open latest data'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('We could not open this folder.'),
      findsOneWidget,
    );
  });

  testWidgets('the Settings button opens the settings', (tester) async {
    await pumpApp(tester, _ready());
    await openTab(tester, 'Settings');
    expect(find.text('Start at login'), findsOneWidget);
  });

  testWidgets('a settings notice shows and can be dismissed', (tester) async {
    final fakes = Fakes(
      store: FakeSettingsStore((
        settings: readySettings,
        notice: SettingsNotice.damaged,
      )),
      discovery: FakeDiscovery(checks: {retailDir: const Valid(retail)}),
    );
    await pumpApp(tester, fakes);
    expect(find.text(en.settingsDamaged), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.text(en.settingsDamaged), findsNothing);
  });

  testWidgets('no backup folder keeps Gather now off', (tester) async {
    final fakes = Fakes(
      store: FakeSettingsStore((
        settings: const Settings(flavorDir: retailDir, wizardDone: true),
        notice: null,
      )),
      discovery: FakeDiscovery(checks: {retailDir: const Valid(retail)}),
    );
    await pumpApp(tester, fakes);
    expect(_enabled(tester, _gatherButton()), isFalse);
  });
}
