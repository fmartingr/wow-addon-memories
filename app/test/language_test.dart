import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memories_core/memories_core.dart' hide UploadState;
import 'package:wow_journey/src/settings/settings.dart';

import 'support/fakes.dart';

Fakes _fakes({String? language, bool registered = false}) {
  final upload = FakeUploadService();
  if (registered) {
    upload.registeredSites.add(readySettings.site);
    upload.fingerprint = '0123456789abcdef';
  }
  return Fakes(
    store: FakeSettingsStore((
      settings: readySettings.copyWith(language: language, upload: registered),
      notice: null,
    )),
    discovery: FakeDiscovery(checks: {retailDir: const Valid(retail)}),
    upload: upload,
  );
}

Future<void> _choose(WidgetTester tester, String name) async {
  final dropdown = find.byKey(const ValueKey('language'));
  await tester.ensureVisible(dropdown);
  await tester.tap(dropdown);
  await tester.pumpAndSettle();
  await tester.tap(find.text(name).last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('language es shows Spanish on the home page', (tester) async {
    await pumpApp(tester, _fakes(language: 'es'));
    expect(find.text('Recopilar ahora'), findsOneWidget);
    expect(find.text('Gather now'), findsNothing);
    expect(find.text('RESUMEN'), findsOneWidget);
    expect(find.text('AJUSTES'), findsOneWidget);
    expect(find.bySemanticsLabel('Ajustes'), findsOneWidget);
  });

  testWidgets('every language shows its own Gather button', (tester) async {
    final words = {
      'de': 'Jetzt sammeln',
      'fr': 'Collecter maintenant',
      'es': 'Recopilar ahora',
      'it': 'Raccogli ora',
      'pt': 'Coletar agora',
    };
    for (final MapEntry(key: code, value: word) in words.entries) {
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, _fakes(language: code));
      expect(find.text(word), findsOneWidget, reason: code);
    }
  });

  testWidgets('System follows an OS in German', (tester) async {
    tester.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
    addTearDown(tester.platformDispatcher.clearLocalesTestValue);
    await pumpApp(tester, _fakes(language: 'es'));
    expect(find.text('Recopilar ahora'), findsOneWidget);
    await openTab(tester, 'Settings');
    await _choose(tester, 'Sistema');
    await openTab(tester, 'Overview');
    expect(find.text('Jetzt sammeln'), findsOneWidget);
    expect(find.text('Recopilar ahora'), findsNothing);
  });

  testWidgets('a language change applies at once to every tab', (tester) async {
    useWindow(tester, height: 1600);
    final fakes = _fakes();
    await pumpApp(tester, fakes);
    await openTab(tester, 'Settings');
    await _choose(tester, 'Italiano');
    expect(find.text('Lingua'), findsOneWidget);
    await openTab(tester, 'Website');
    expect(find.text('Registrazione'), findsOneWidget);
    await openTab(tester, 'Overview');
    expect(find.text('Raccogli ora'), findsOneWidget);
    expect(fakes.store.saved.last.language, 'it');
  });

  testWidgets('a notice on the screen changes language with the app', (
    tester,
  ) async {
    useWindow(tester, height: 2400);
    final fakes = _fakes(registered: true);
    fakes.upload.syncError = const UploadException(
      'network',
      'Could not reach example.',
    );
    await pumpApp(tester, fakes);
    await openTab(tester, 'Website');
    await tester.tap(find.text('Upload now'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not reach'), findsOneWidget);

    await openTab(tester, 'Settings');
    await _choose(tester, 'Deutsch');
    await openTab(tester, 'Website');
    expect(find.textContaining('Could not reach'), findsNothing);
    expect(find.textContaining('nicht erreichbar'), findsOneWidget);
  });

  testWidgets('the wizard follows the language too', (tester) async {
    final fakes = Fakes(
      store: FakeSettingsStore((
        settings: const Settings(language: 'fr'),
        notice: null,
      )),
      discovery: FakeDiscovery(found: [retail]),
    );
    await pumpApp(tester, fakes);
    expect(find.text('Étape 1 sur 3'), findsOneWidget);
    expect(find.text('Suivant'), findsOneWidget);
  });
}
