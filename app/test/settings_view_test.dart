import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memories_core/memories_core.dart';
import 'package:wow_journey/src/version.dart';

import 'support/fakes.dart';
import 'support/texts.dart';

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
  await openTab(tester, 'Settings');
  return fakes;
}

Finder _change(String label) => find.bySemanticsLabel(label);

void main() {
  testWidgets('shows the folders, the switches and the version', (
    tester,
  ) async {
    useWindow(tester, height: 1600);
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

  group('the Language row', () {
    Finder dropdown() => find.byKey(const ValueKey('language'));
    Locale? appLocale(WidgetTester tester) =>
        tester.widget<MaterialApp>(find.byType(MaterialApp)).locale;

    Future<void> choose(WidgetTester tester, String name) async {
      await tester.ensureVisible(dropdown());
      await tester.tap(dropdown());
      await tester.pumpAndSettle();
      await tester.tap(find.text(name).last);
      await tester.pumpAndSettle();
    }

    testWidgets('shows System, and the app follows the system', (tester) async {
      useWindow(tester, height: 1600);
      await _openSettings(tester);
      expect(find.text('Language'), findsOneWidget);
      expect(
        find.descendant(of: dropdown(), matching: find.text('System')),
        findsOneWidget,
      );
      expect(appLocale(tester), isNull);
    });

    testWidgets('lists System and the 6 languages by their own names', (
      tester,
    ) async {
      useWindow(tester, height: 1600);
      await _openSettings(tester);
      await tester.ensureVisible(dropdown());
      await tester.tap(dropdown());
      await tester.pumpAndSettle();
      for (final name in [
        'System',
        'English',
        'Deutsch',
        'Français',
        'Español',
        'Italiano',
        'Português',
      ]) {
        expect(find.text(name), findsWidgets, reason: name);
      }
    });

    testWidgets('Deutsch saves de at once and sets the locale', (tester) async {
      useWindow(tester, height: 1600);
      final fakes = await _openSettings(tester);
      await choose(tester, 'Deutsch');
      expect(fakes.store.saved.last.language, 'de');
      expect(appLocale(tester), const Locale('de'));
      expect(
        find.descendant(of: dropdown(), matching: find.text('Deutsch')),
        findsOneWidget,
      );
    });

    testWidgets('System after a language saves null', (tester) async {
      useWindow(tester, height: 1600);
      final fakes = await _openSettings(tester);
      await choose(tester, 'Français');
      expect(fakes.store.saved.last.language, 'fr');
      await choose(tester, 'System');
      expect(fakes.store.saved.last.language, isNull);
      expect(appLocale(tester), isNull);
    });

    testWidgets('a saved language is used at the next start', (tester) async {
      useWindow(tester, height: 1600);
      final fakes = Fakes(
        store: FakeSettingsStore((
          settings: readySettings.copyWith(language: 'it'),
          notice: null,
        )),
        discovery: FakeDiscovery(checks: {retailDir: const Valid(retail)}),
      );
      await pumpApp(tester, fakes);
      expect(appLocale(tester), const Locale('it'));
    });

    testWidgets('System follows the language of the operating system', (
      tester,
    ) async {
      tester.platformDispatcher.localesTestValue = const [Locale('pt', 'PT')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await _openSettings(tester);
      final context = tester.element(find.byType(Scaffold).first);
      expect(Localizations.localeOf(context), const Locale('pt'));
    });

    testWidgets('an unsupported system language gives English', (tester) async {
      tester.platformDispatcher.localesTestValue = const [Locale('ru', 'RU')];
      addTearDown(tester.platformDispatcher.clearLocalesTestValue);
      await _openSettings(tester);
      final context = tester.element(find.byType(Scaffold).first);
      expect(Localizations.localeOf(context), const Locale('en'));
      expect(find.text('Language'), findsOneWidget);
    });
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
    await openTab(tester, 'Overview');
    expect(find.text(watchingText), findsNothing);

    await openTab(tester, 'Settings');
    await tester.tap(find.text('Watch'));
    await tester.pumpAndSettle();
    expect(fakes.signature.calls, hasLength(3));
    await tester.pump(const Duration(seconds: 10));
    expect(fakes.signature.calls, hasLength(4));
    await openTab(tester, 'Overview');
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
    await openTab(tester, 'Settings');
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
