// Writes PNG pictures of the app screens, for the theme parity review (see .claude/skills/theme-parity). It does nothing
// unless THEME_PREVIEW_DIR names a folder: `make app-shots`.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart' show RepaintBoundary;
import 'package:flutter/material.dart' show Scaffold;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AssetImage, precacheImage;
import 'package:flutter_test/flutter_test.dart';
import 'package:memories_core/memories_core.dart';
import 'package:wow_journey/src/gather/gather_controller.dart';

import 'support/fakes.dart';

// flutter test draws every font as boxes, so the picture loads the real ones.
Future<void> _loadFonts() async {
  Future<ByteData> file(String path) async =>
      ByteData.sublistView(File(path).readAsBytesSync());
  final cinzel = FontLoader('Cinzel')
    ..addFont(file('assets/fonts/Cinzel-Variable.ttf'));
  final alegreya = FontLoader('Alegreya Sans')
    ..addFont(file('assets/fonts/AlegreyaSans-400.ttf'))
    ..addFont(file('assets/fonts/AlegreyaSans-500.ttf'))
    ..addFont(file('assets/fonts/AlegreyaSans-700.ttf'));
  final root = Platform.environment['FLUTTER_ROOT'];
  final icons = FontLoader('MaterialIcons');
  if (root != null) {
    icons.addFont(
      file(
        '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
      ),
    );
  }
  await Future.wait([cinzel.load(), alegreya.load(), icons.load()]);
}

Future<void> _shot(WidgetTester tester, String dir, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    return image.toByteData(format: ui.ImageByteFormat.png);
  });
  File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
}

void main() {
  final dir = Platform.environment['THEME_PREVIEW_DIR'];
  testWidgets('theme preview', skip: dir == null, (tester) async {
    Directory(dir!).createSync(recursive: true);
    await tester.runAsync(_loadFonts);
    final fakes = Fakes(
      store: FakeSettingsStore((settings: readySettings, notice: null)),
      discovery: FakeDiscovery(checks: {retailDir: const Valid(retail)}),
      gather: FakeGatherService(
        snapshot: const BackupSnapshot(
          characters: [
            CharacterSummary(
              id: 'a',
              name: 'Neral',
              realm: 'Brumamar',
              level: 11,
              className: 'ROGUE',
            ),
            CharacterSummary(
              id: 'b',
              name: 'Nandu',
              realm: 'Brumamar',
              level: 10,
              className: 'HUNTER',
            ),
          ],
          lines: 2261,
          screenshots: 57,
        ),
      ),
    );
    useWindow(tester, width: 1000, height: 900);
    await pumpApp(tester, fakes);
    await tester.runAsync(
      () => precacheImage(
        const AssetImage('assets/crest.png'),
        tester.element(find.byType(Scaffold).first),
      ),
    );
    await tester.pumpAndSettle();
    await _shot(tester, dir, 'overview');
    await openTab(tester, 'Website');
    await _shot(tester, dir, 'website');
    await openTab(tester, 'Settings');
    await _shot(tester, dir, 'settings');
    useWindow(tester, width: 400, height: 800);
    await tester.pumpAndSettle();
    await openTab(tester, 'Overview');
    await _shot(tester, dir, 'overview-narrow');
  });

  testWidgets('theme preview of the wizard', skip: dir == null, (tester) async {
    Directory(dir!).createSync(recursive: true);
    await tester.runAsync(_loadFonts);
    useWindow(tester, width: 1000, height: 700);
    await pumpApp(
      tester,
      Fakes(discovery: FakeDiscovery(found: [retail, forever])),
    );
    await _shot(tester, dir, 'wizard');
  });
}
