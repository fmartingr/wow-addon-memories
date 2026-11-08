import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memories_core/memories_core.dart';
import 'package:wow_journey/src/gather/gather_controller.dart';

import 'support/fakes.dart';

Fakes _home() => Fakes(
  store: FakeSettingsStore((settings: readySettings, notice: 'A notice.')),
  discovery: FakeDiscovery(checks: {retailDir: const Valid(retail)}),
  gather:
      FakeGatherService(
          snapshot: const BackupSnapshot(
            characters: [
              CharacterSummary(
                id: 'eu-los-errantes-a-very-long-name',
                name: 'Averyveryverylongname',
                realm: 'Los Errantes de la Noche Eterna',
                level: 60,
                className: 'DEATHKNIGHT',
              ),
            ],
          ),
        )
        ..next = (
          result: GatherResult(
            issues: [
              for (final c in GatherIssueCode.values)
                issue(c, path: '$retailDir/WTF/Account/A/SavedVariables/x.lua'),
            ],
          ),
          snapshot: const BackupSnapshot(),
        ),
);

void main() {
  testWidgets('the app shows its title', (tester) async {
    await pumpApp(tester, _home());
    expect(find.text('WoW Journey'), findsOneWidget);
  });

  group('at 480 px and text scale 1.5 nothing overflows', () {
    testWidgets('wizard', (tester) async {
      useWindow(tester, width: 480, textScale: 1.5);
      await pumpApp(
        tester,
        Fakes(discovery: FakeDiscovery(found: [retail, forever])),
      );
      for (var step = 0; step < 2; step++) {
        expect(tester.takeException(), isNull);
        await tester.tap(find.widgetWithText(FilledButton, 'Next'));
        await tester.pumpAndSettle();
      }
      expect(tester.takeException(), isNull);
      expect(find.text('Step 3 of 3'), findsOneWidget);
    });

    testWidgets('home with every problem', (tester) async {
      useWindow(tester, width: 480, textScale: 1.5);
      await pumpApp(tester, _home());
      await tester.tap(find.text('Gather now'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.drag(find.byType(ListView), const Offset(0, -20000));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Open latest data'), findsOneWidget);
    });

    testWidgets('settings', (tester) async {
      useWindow(tester, width: 480, textScale: 1.5);
      await pumpApp(tester, _home());
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the controls have Semantics labels', (tester) async {
    final fakes = _home();
    fakes.gather.next = null;
    await pumpApp(tester, fakes);

    final button = isSemantics(isButton: true, hasTapAction: true);
    for (final label in [
      'Gather now',
      'Open backup folder',
      'Open latest data',
    ]) {
      expect(tester.getSemantics(find.bySemanticsLabel(label)), button);
    }
    for (final tip in ['Settings', 'Dismiss']) {
      expect(
        tester.getSemantics(find.byTooltip(tip)),
        isSemantics(tooltip: tip, isButton: true, hasTapAction: true),
      );
    }
    expect(find.bySemanticsLabel('Status: Never gathered'), findsOneWidget);

    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    for (final label in ['Change the WoW folder', 'Change the backup folder']) {
      expect(tester.getSemantics(find.bySemanticsLabel(label)), button);
    }
    for (final label in ['Watch', 'Start at login']) {
      expect(
        find.bySemanticsLabel(RegExp('^$label')),
        findsOneWidget,
        reason: label,
      );
    }
  });

  testWidgets('the wizard buttons have Semantics labels', (tester) async {
    await pumpApp(tester, Fakes(discovery: FakeDiscovery(found: [retail])));
    final button = isSemantics(isButton: true, hasTapAction: true);
    expect(tester.getSemantics(find.bySemanticsLabel('Next step')), button);
    expect(
      tester.getSemantics(find.bySemanticsLabel('Change the WoW folder')),
      button,
    );
    expect(find.bySemanticsLabel('WoW folder: $retailDir'), findsOneWidget);
  });

  testWidgets('Tab moves the focus from Gather now down to the open buttons', (
    tester,
  ) async {
    final fakes = _home();
    fakes.gather.next = null;
    await pumpApp(tester, fakes);

    FocusNode nodeOf(String text) => Focus.of(tester.element(find.text(text)));
    final wanted = [
      nodeOf('Gather now'),
      nodeOf('Open backup folder'),
      nodeOf('Open latest data'),
    ];
    final seen = <FocusNode>[];
    for (var i = 0; i < 20; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      final node = FocusManager.instance.primaryFocus;
      if (node != null && wanted.contains(node) && !seen.contains(node)) {
        seen.add(node);
      }
    }
    expect(seen, wanted);
  });
}
