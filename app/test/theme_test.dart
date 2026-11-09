import 'package:flutter/material.dart';

import 'dart:ui' show Canvas, PictureRecorder, Rect;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wow_journey/src/theme/ak_theme.dart';
import 'package:wow_journey/src/theme/ak_widgets.dart';
import 'package:wow_journey/src/theme/tokens.dart';

void _noop() {}

Widget _host(Widget child) => MaterialApp(
  theme: buildAkTheme(),
  home: Scaffold(body: child),
);

void main() {
  group('theme', () {
    test('is dark and uses the tokens of the website', () {
      final t = buildAkTheme();
      expect(t.brightness, Brightness.dark);
      expect(t.colorScheme.primary, Tokens.gold);
      expect(t.colorScheme.surface, Tokens.surface);
      expect(t.scaffoldBackgroundColor, Tokens.bg);
      expect(t.colorScheme.error, Tokens.red);
      expect(t.textTheme.titleMedium?.fontFamily, Tokens.displayFamily);
      expect(t.textTheme.bodyMedium?.fontFamily, Tokens.bodyFamily);
    });

    test('cards and dialogs are panels, buttons have a gradient', () {
      final t = buildAkTheme();
      expect(t.cardTheme.shape, isA<AkPanelBorder>());
      expect(t.dialogTheme.shape, isA<AkPanelBorder>());
      expect(t.filledButtonTheme.style?.backgroundBuilder, isNotNull);
      expect(t.outlinedButtonTheme.style?.backgroundBuilder, isNotNull);
    });

    test('the tokens match the class and quality colours of the game', () {
      expect(classColours.keys, hasLength(9));
      expect(classColours['HUNTER'], const Color(0xFFAAD372));
      expect(qualityColours, hasLength(6));
      expect(qualityColours[4], const Color(0xFFA335EE));
    });

    test('a panel border paints without error', () {
      const border = AkPanelBorder();
      final rec = PictureRecorder();
      border.paint(Canvas(rec), const Rect.fromLTWH(0, 0, 100, 50));
      expect(border.scale(2), isA<AkPanelBorder>());
      expect(
        border.getInnerPath(const Rect.fromLTWH(0, 0, 100, 50)),
        isNotNull,
      );
    });
  });

  group('button states', () {
    testWidgets('a focused button has a gold-light ring', (tester) async {
      await tester.pumpWidget(
        _host(FilledButton(onPressed: () {}, child: const Text('Go'))),
      );
      bool ring() =>
          tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).any((b) {
            final d = b.decoration;
            return d is BoxDecoration &&
                d.border is Border &&
                (d.border! as Border).top.color == Tokens.goldLight &&
                (d.border! as Border).top.width == 2;
          });
      expect(ring(), isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(ring(), isTrue);
    });

    testWidgets('a disabled text button and switch look disabled', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const Column(
            children: [
              TextButton(onPressed: null, child: Text('Off')),
              TextButton(onPressed: _noop, child: Text('On')),
              Switch(value: true, onChanged: null),
            ],
          ),
        ),
      );
      Color? ink(String label) => tester
          .widget<DefaultTextStyle>(
            find
                .descendant(
                  of: find.widgetWithText(TextButton, label),
                  matching: find.byType(DefaultTextStyle),
                )
                .first,
          )
          .style
          .color;
      expect(ink('Off'), isNot(ink('On')));
      final track = tester.widget<Switch>(find.byType(Switch));
      expect(track.onChanged, isNull);
    });
  });

  group('AkTabBar', () {
    Widget bar(ValueChanged<int> on, {int selected = 0}) => _host(
      AkTabBar(
        tabs: const [
          AkTab(label: 'One'),
          AkTab(label: 'Two'),
          AkTab(label: 'Three'),
        ],
        selected: selected,
        onSelected: on,
      ),
    );

    testWidgets('a tap selects a tab', (tester) async {
      final picked = <int>[];
      await tester.pumpWidget(bar(picked.add));
      await tester.tap(find.byKey(const ValueKey('tab-Two')));
      expect(picked, [1]);
    });

    testWidgets('the selected tab says so to the screen reader', (
      tester,
    ) async {
      await tester.pumpWidget(bar((_) {}, selected: 2));
      expect(
        tester.getSemantics(find.bySemanticsLabel('Three')),
        isSemantics(
          label: 'Three',
          isButton: true,
          hasTapAction: true,
          hasSelectedState: true,
          isSelected: true,
        ),
      );
      expect(
        tester.getSemantics(find.bySemanticsLabel('One')),
        isSemantics(
          label: 'One',
          isButton: true,
          hasTapAction: true,
          hasSelectedState: true,
        ),
      );
    });

    testWidgets('Left and Right move the selection and wrap', (tester) async {
      final picked = <int>[];
      await tester.pumpWidget(bar(picked.add));
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      expect(picked, [1, 2]);
    });

    testWidgets('Left and Right move the focus with the selection', (
      tester,
    ) async {
      var selected = 0;
      await tester.pumpWidget(
        _host(
          StatefulBuilder(
            builder: (context, set) => AkTabBar(
              tabs: const [
                AkTab(label: 'One'),
                AkTab(label: 'Two'),
              ],
              selected: selected,
              onSelected: (i) => set(() => selected = i),
            ),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(selected, 1);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Two')),
        isSemantics(
          label: 'Two',
          isFocused: true,
          isFocusable: true,
          isButton: true,
          hasTapAction: true,
          hasSelectedState: true,
          isSelected: true,
        ),
      );
    });

    testWidgets('a narrow bar drops the icons and fits', (tester) async {
      tester.view.physicalSize = const Size(300, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        _host(
          AkTabBar(
            tabs: const [
              AkTab(label: 'Overview', icon: Icons.home),
              AkTab(label: 'Website', icon: Icons.cloud),
              AkTab(label: 'Settings', icon: Icons.settings),
            ],
            selected: 0,
            onSelected: (_) {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.home), findsNothing);
    });
  });

  group('small components', () {
    testWidgets('AkTag shows its label', (tester) async {
      await tester.pumpWidget(
        _host(const AkTag('Hardcore', kind: AkTagKind.hardcore)),
      );
      expect(find.text('Hardcore'), findsOneWidget);
    });

    testWidgets('AkPanelTitle is a header and AkHeader shows the title', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const Column(
            children: [
              AkHeader(title: 'WoW Journey'),
              AkPanelTitle('Backup'),
            ],
          ),
        ),
      );
      expect(find.text('WoW Journey'), findsOneWidget);
      expect(find.text('Backup'), findsOneWidget);
    });
  });
}
