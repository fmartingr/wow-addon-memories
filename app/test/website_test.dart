import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memories_core/memories_core.dart' hide UploadState;
import 'package:wow_journey/src/settings/settings.dart';
import 'package:wow_journey/src/ui/messages.dart';

import 'support/fakes.dart';

const String site = 'https://wowjourney.xyz';

const RemoteCharacter nandu = RemoteCharacter(
  path: 'wow/eu/brumamar/nandu',
  url: '$site/wow/eu/brumamar/nandu/',
  guid: 'Player-1-00000001',
  steps: 15,
  updated: 1,
);

Fakes _fakes({
  Settings settings = readySettings,
  bool registered = false,
  List<RemoteCharacter> characters = const [],
  String screenshots = 'none',
}) {
  final upload = FakeUploadService()
    ..meInfo = MeInfo(screenshots: screenshots, characters: characters);
  if (registered) {
    upload.registeredSites.add(settings.site);
    upload.fingerprint = '0123456789abcdef';
  }
  return Fakes(
    store: FakeSettingsStore((settings: settings, notice: null)),
    discovery: FakeDiscovery(checks: {retailDir: const Valid(retail)}),
    upload: upload,
  );
}

Future<void> _openSettings(WidgetTester tester, Fakes fakes) async {
  useWindow(tester, height: 2400);
  await pumpApp(tester, fakes);
  await openTab(tester, 'Website');
}

Finder _field(String label) => find.widgetWithText(TextField, label);

Finder _button(String label) => find.ancestor(
  of: find.text(label),
  matching: find.byWidgetPredicate((w) => w is ButtonStyleButton),
);

bool _enabled(WidgetTester tester, Finder button) =>
    tester.widget<ButtonStyleButton>(button).onPressed != null;

SwitchListTile _uploadSwitch(WidgetTester tester) => tester
    .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Upload'));

void main() {
  group('Website tab, registration', () {
    testWidgets('shows the default address and asks for an invite code', (
      tester,
    ) async {
      await _openSettings(tester, _fakes());
      expect(find.text(websiteRegistrationTitle), findsOneWidget);
      expect(
        tester.widget<TextField>(_field(websiteAddressLabel)).controller!.text,
        defaultSite,
      );
      expect(_field(inviteCodeLabel), findsOneWidget);
      expect(_button(registerLabel), findsOneWidget);
      expect(find.text(notRegisteredText(defaultSite)), findsOneWidget);
      expect(_uploadSwitch(tester).onChanged, isNull);
      expect(_uploadSwitch(tester).value, isFalse);
      expect(find.text(lostKeyText), findsNothing);
    });

    testWidgets('Check shows the site name and the invite mode', (
      tester,
    ) async {
      final fakes = _fakes();
      await _openSettings(tester, fakes);
      await tester.tap(_button(checkSiteLabel));
      await tester.pumpAndSettle();
      expect(fakes.upload.calls, ['info $site']);
      expect(find.textContaining('Found Journey Site'), findsOneWidget);
      expect(find.textContaining('invite code'), findsWidgets);
      expect(_field(inviteCodeLabel), findsOneWidget);
    });

    testWidgets('open registration shows Register with no code field', (
      tester,
    ) async {
      final fakes = _fakes();
      fakes.upload.siteInfo = const SiteInfo(
        api: 1,
        name: 'Open Site',
        registration: 'open',
      );
      await _openSettings(tester, fakes);
      await tester.tap(_button(checkSiteLabel));
      await tester.pumpAndSettle();
      expect(find.textContaining('Anybody can register'), findsOneWidget);
      expect(_field(inviteCodeLabel), findsNothing);

      await tester.tap(_button(registerLabel));
      await tester.pumpAndSettle();
      expect(fakes.upload.registrations, [(site, null)]);
      expect(find.text(registeredText(site)), findsOneWidget);
      expect(_button(registerLabel), findsNothing);
    });

    testWidgets('Register sends the invite code and unlocks the switch', (
      tester,
    ) async {
      final fakes = _fakes();
      await _openSettings(tester, fakes);
      await tester.enterText(_field(inviteCodeLabel), 'ABCD1234');
      await tester.tap(_button(registerLabel));
      await tester.pumpAndSettle();

      expect(fakes.upload.registrations, [(site, 'ABCD1234')]);
      expect(find.text(registeredText(site)), findsOneWidget);
      expect(find.text(fingerprintText('0123456789abcdef')), findsOneWidget);
      expect(find.text(lostKeyText), findsOneWidget);
      expect(_uploadSwitch(tester).onChanged, isNotNull);
      expect(find.text(registerLabel), findsNothing);
    });

    testWidgets('a refused code shows the message of the website', (
      tester,
    ) async {
      final fakes = _fakes();
      fakes.upload.registerError = const UploadException(
        'invite_invalid',
        'This invite code is not valid. Ask the website admin for a new one.',
        status: 403,
      );
      await _openSettings(tester, fakes);
      await tester.enterText(_field(inviteCodeLabel), 'nope');
      await tester.tap(_button(registerLabel));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'This invite code is not valid. Ask the website admin for a new one.',
        ),
        findsOneWidget,
      );
      expect(_uploadSwitch(tester).onChanged, isNull);
    });

    testWidgets('an address with http on another host gets a plain message', (
      tester,
    ) async {
      final fakes = _fakes();
      await _openSettings(tester, fakes);
      await tester.enterText(_field(websiteAddressLabel), 'http://example.com');
      await tester.tap(_button(checkSiteLabel));
      await tester.pumpAndSettle();
      expect(find.textContaining('must start with https://'), findsOneWidget);
      expect(fakes.upload.calls, isEmpty);
      expect(fakes.store.saved, isEmpty);

      await tester.enterText(_field(websiteAddressLabel), 'not a site');
      await tester.tap(_button(registerLabel));
      await tester.pumpAndSettle();
      expect(fakes.upload.registrations, isEmpty);
      expect(
        tester
            .widget<TextField>(_field(websiteAddressLabel))
            .decoration!
            .errorText,
        startsWith('The website address'),
      );
    });

    testWidgets('a new address is saved and starts unregistered', (
      tester,
    ) async {
      final fakes = _fakes(
        settings: readySettings.copyWith(upload: true),
        registered: true,
      );
      await _openSettings(tester, fakes);
      expect(find.text(registeredText(site)), findsOneWidget);

      await tester.enterText(
        _field(websiteAddressLabel),
        'http://localhost:8080/',
      );
      await tester.tap(_button(checkSiteLabel));
      await tester.pumpAndSettle();

      expect(fakes.store.saved.last.site, 'http://localhost:8080');
      expect(fakes.store.saved.last.upload, isFalse);
      expect(find.text(notRegisteredText('http://localhost:8080')), findsOne);
      expect(_uploadSwitch(tester).onChanged, isNull);
      expect(fakes.upload.registeredSites, {site});
      expect(fakes.upload.calls, contains('info http://localhost:8080'));
    });

    testWidgets('the Upload switch saves its value', (tester) async {
      final fakes = _fakes(registered: true);
      await _openSettings(tester, fakes);
      expect(_uploadSwitch(tester).value, isFalse);
      await tester.tap(find.widgetWithText(SwitchListTile, 'Upload'));
      await tester.pumpAndSettle();
      expect(fakes.store.saved.last.upload, isTrue);
      expect(_uploadSwitch(tester).value, isTrue);
      expect(fakes.upload.syncs, isEmpty);
    });

    testWidgets('Request screenshots asks once and shows the state', (
      tester,
    ) async {
      final fakes = _fakes(registered: true);
      await _openSettings(tester, fakes);
      expect(find.text(screenshotsText('none')), findsOneWidget);
      await tester.tap(_button(requestScreenshotsLabel));
      await tester.pumpAndSettle();
      expect(fakes.upload.calls, contains('requestScreenshots $site'));
      expect(find.text(screenshotsText('pending')), findsOneWidget);
      expect(_enabled(tester, _button(requestScreenshotsLabel)), isFalse);
    });

    testWidgets('an approved key shows the state and no request', (
      tester,
    ) async {
      await _openSettings(
        tester,
        _fakes(registered: true, screenshots: 'approved'),
      );
      expect(find.text(screenshotsText('approved')), findsOneWidget);
      expect(_enabled(tester, _button(requestScreenshotsLabel)), isFalse);
    });
  });

  group('Website tab, card', () {
    testWidgets('an unregistered key points to the registration below', (
      tester,
    ) async {
      final fakes = _fakes();
      useWindow(tester, height: 2400);
      await pumpApp(tester, fakes);
      await openTab(tester, 'Website');
      expect(find.text(cardNotRegisteredText(site)), findsOneWidget);
      expect(find.text(uploadNowLabel), findsNothing);
      expect(find.text(websiteAddressLabel), findsOneWidget);
      expect(find.text(registerLabel), findsOneWidget);
    });

    testWidgets('with Upload off, the card says so and has no Upload now', (
      tester,
    ) async {
      final fakes = _fakes(registered: true, characters: [nandu]);
      useWindow(tester, height: 2400);
      await pumpApp(tester, fakes);
      await openTab(tester, 'Website');
      expect(find.text(cardUploadOffText), findsOneWidget);
      expect(find.text(uploadNowLabel), findsNothing);
      expect(find.text(copyLinkLabel), findsOneWidget);
      expect(find.text(unlistedText), findsOneWidget);
    });

    testWidgets('Upload now uploads and shows the result', (tester) async {
      final fakes = _fakes(
        settings: readySettings.copyWith(upload: true),
        registered: true,
        characters: [nandu],
      );
      fakes.clock = DateTime.now;
      fakes.upload.report = const SyncReport(
        screenshots: 'none',
        characters: [
          CharacterResult(
            id: 'eu-brumamar-nandu',
            path: 'wow/eu/brumamar/nandu',
            status: SyncStatus.uploaded,
          ),
        ],
      );
      useWindow(tester, height: 2400);
      await pumpApp(tester, fakes);
      await openTab(tester, 'Website');
      expect(find.text('Nothing uploaded yet.'), findsOneWidget);

      await tester.tap(find.text(uploadNowLabel));
      await tester.pumpAndSettle();

      expect(fakes.upload.syncs, [(site, '/backups/WoW Journey/latest')]);
      expect(fakes.upload.resends, [true]);
      expect(find.textContaining('Last upload'), findsOneWidget);
      expect(find.text('Uploaded 1 character.'), findsOneWidget);
      expect(find.text(nandu.url), findsOneWidget);
    });

    testWidgets('a running upload shows a determinate progress bar', (
      tester,
    ) async {
      final fakes = _fakes(
        settings: readySettings.copyWith(upload: true),
        registered: true,
      );
      fakes.upload.pendingSync = Completer<SyncReport>();
      useWindow(tester, height: 2400);
      await pumpApp(tester, fakes);
      await openTab(tester, 'Website');
      await tester.tap(find.text(uploadNowLabel));
      await tester.pump();

      LinearProgressIndicator bar() => tester.widget<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bar().value, isNull);
      expect(find.text(uploadingLabel), findsWidgets);

      fakes.upload.onProgress!(12, 90);
      await tester.pump();
      expect(bar().value, closeTo(12 / 90, 1e-9));
      expect(find.text('Uploading 12 of 90'), findsOneWidget);

      fakes.upload.pendingSync!.complete(
        const SyncReport(screenshots: 'none', characters: []),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('a paused upload says it continues, with no error', (
      tester,
    ) async {
      final fakes = _fakes(
        settings: readySettings.copyWith(upload: true),
        registered: true,
      );
      fakes.upload.syncError = const UploadException(
        'rate_limited',
        'Too many requests.',
        status: 429,
        recoverable: true,
      );
      useWindow(tester, height: 2400);
      await pumpApp(tester, fakes);
      await openTab(tester, 'Website');
      await tester.tap(find.text(uploadNowLabel));
      await tester.pumpAndSettle();
      expect(find.text(uploadPausedText), findsOneWidget);
      expect(
        uploadPausedText,
        'Upload paused. It continues after the next gather.',
      );
      expect(find.textContaining('Too many requests'), findsNothing);
      expect(find.text(uploadNowLabel), findsOneWidget);
    });

    testWidgets('a failed upload shows a plain message', (tester) async {
      final fakes = _fakes(
        settings: readySettings.copyWith(upload: true),
        registered: true,
      );
      fakes.upload.syncError = const UploadException(
        'bad_signature',
        'The website did not accept the request. Check that the clock of '
            'this computer is right.',
        status: 401,
      );
      useWindow(tester, height: 2400);
      await pumpApp(tester, fakes);
      await openTab(tester, 'Website');
      await tester.tap(find.text(uploadNowLabel));
      await tester.pumpAndSettle();
      expect(find.textContaining('clock of this computer'), findsOneWidget);
      expect(find.textContaining('Exception'), findsNothing);
    });

    testWidgets('an upload problem shows on the Overview tab too', (
      tester,
    ) async {
      final fakes = _fakes(
        settings: readySettings.copyWith(upload: true),
        registered: true,
      );
      fakes.upload.syncError = const UploadException(
        'bad_signature',
        'The website did not accept the request.',
        status: 401,
      );
      useWindow(tester, height: 2400);
      await pumpApp(tester, fakes);
      await openTab(tester, 'Website');
      await tester.tap(find.text(uploadNowLabel));
      await tester.pumpAndSettle();
      await openTab(tester, 'Overview');
      expect(find.textContaining('did not accept the request'), findsOneWidget);
      await tester.tap(find.text(showWebsiteLabel));
      await tester.pumpAndSettle();
      expect(find.text(uploadNowLabel), findsOneWidget);
    });

    testWidgets('a revoked key turns Upload off and says so', (tester) async {
      final fakes = _fakes(
        settings: readySettings.copyWith(upload: true),
        registered: true,
      );
      fakes.upload.syncError = const UploadException(
        'key_revoked',
        'x',
        status: 403,
      );
      useWindow(tester, height: 2400);
      await pumpApp(tester, fakes);
      await openTab(tester, 'Website');
      await tester.tap(find.text(uploadNowLabel));
      await tester.pumpAndSettle();
      expect(find.text(keyRevokedText(site)), findsOneWidget);
      expect(fakes.store.saved.last.upload, isFalse);
      expect(find.text(cardUploadOffText), findsOneWidget);
    });

    testWidgets('a gather uploads when Upload is on and the key registered', (
      tester,
    ) async {
      final fakes = _fakes(
        settings: readySettings.copyWith(upload: true),
        registered: true,
      );
      useWindow(tester, height: 2400);
      await pumpApp(tester, fakes);
      await tester.tap(find.text('Gather now'));
      await tester.pumpAndSettle();
      expect(fakes.gather.calls, hasLength(1));
      expect(fakes.upload.syncs, hasLength(1));
      expect(fakes.upload.resends, [false]);
    });

    testWidgets('a gather uploads nothing when Upload is off', (tester) async {
      final fakes = _fakes(registered: true);
      useWindow(tester, height: 2400);
      await pumpApp(tester, fakes);
      await tester.tap(find.text('Gather now'));
      await tester.pumpAndSettle();
      expect(fakes.gather.calls, hasLength(1));
      expect(fakes.upload.syncs, isEmpty);
    });

    testWidgets('Copy link puts the link on the clipboard', (tester) async {
      final copied = <String?>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied.add((call.arguments as Map)['text'] as String?);
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final fakes = _fakes(registered: true, characters: [nandu]);
      useWindow(tester, height: 2400);
      await pumpApp(tester, fakes);
      await openTab(tester, 'Website');
      await tester.tap(find.text(copyLinkLabel));
      await tester.pumpAndSettle();
      expect(copied, [nandu.url]);
      expect(find.text(linkCopiedText), findsOneWidget);
    });

    testWidgets('Remove asks first, and Cancel keeps the character', (
      tester,
    ) async {
      final fakes = _fakes(registered: true, characters: [nandu]);
      useWindow(tester, height: 2400);
      await pumpApp(tester, fakes);
      await openTab(tester, 'Website');
      await tester.tap(find.text(removeFromWebsiteLabel));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Remove nandu from wowjourney.xyz? The page and its data '
          'are deleted.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text(cancelLabel));
      await tester.pumpAndSettle();
      expect(fakes.upload.deletions, isEmpty);
      expect(find.text(nandu.url), findsOneWidget);
    });

    testWidgets('Remove deletes the character from the website', (
      tester,
    ) async {
      final fakes = _fakes(registered: true, characters: [nandu]);
      useWindow(tester, height: 2400);
      await pumpApp(tester, fakes);
      await openTab(tester, 'Website');
      await tester.tap(find.text(removeFromWebsiteLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(removeLabel));
      await tester.pumpAndSettle();
      expect(fakes.upload.deletions, [(site, nandu.path)]);
      expect(find.text(nandu.url), findsNothing);
      expect(find.text(removedText('nandu')), findsOneWidget);
    });

    testWidgets('a failed removal keeps the character and says why', (
      tester,
    ) async {
      final fakes = _fakes(registered: true, characters: [nandu]);
      fakes.upload.deleteError = const UploadException(
        'network',
        'Could not reach wowjourney.xyz. Check the internet connection and '
            'the website address.',
      );
      useWindow(tester, height: 2400);
      await pumpApp(tester, fakes);
      await openTab(tester, 'Website');
      await tester.tap(find.text(removeFromWebsiteLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(removeLabel));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not reach'), findsOneWidget);
      expect(find.text(nandu.url), findsOneWidget);
    });
  });
}
