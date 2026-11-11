import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memories_core/memories_core.dart' hide UploadState;
import 'package:path/path.dart' as p;
import 'package:wow_journey/src/gather/gather_controller.dart';
import 'package:wow_journey/src/settings/settings.dart';

import 'support/fakes.dart';
import 'support/texts.dart';

const String site = 'https://wowjourney.xyz';

const RemoteCharacter nandu = RemoteCharacter(
  path: 'wow/eu/brumamar/nandu',
  url: '$site/wow/eu/brumamar/nandu/',
  guid: 'Player-1-00000001',
  steps: 15,
  updated: 1,
);

const CharacterSummary localNandu = CharacterSummary(
  id: 'eu-brumamar-nandu',
  name: 'nandu',
  realm: 'Brumamar',
  level: 70,
  className: 'HUNTER',
  path: 'wow/eu/brumamar/nandu',
);

CharacterSummary _local(String name) => CharacterSummary(
  id: 'eu-brumamar-$name',
  name: name,
  realm: 'Brumamar',
  level: 60,
  path: 'wow/eu/brumamar/$name',
);

/// [local] are the characters of the backup folder, and [selected] the paths
/// that the state file holds as chosen for the site. By default the one
/// character of the folder is chosen.
Fakes _fakes({
  Settings settings = readySettings,
  bool registered = false,
  List<RemoteCharacter> characters = const [],
  List<CharacterSummary> local = const [localNandu],
  Set<String> selected = const {'wow/eu/brumamar/nandu'},
  String screenshots = 'none',
}) {
  final upload = FakeUploadService()
    ..meInfo = MeInfo(screenshots: screenshots, characters: characters)
    ..selections[settings.site] = {...selected};
  if (registered) {
    upload.registeredSites.add(settings.site);
    upload.fingerprint = '0123456789abcdef';
  }
  return Fakes(
    store: FakeSettingsStore((settings: settings, notice: null)),
    discovery: FakeDiscovery(checks: {retailDir: const Valid(retail)}),
    gather: FakeGatherService(snapshot: BackupSnapshot(characters: local)),
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
      expect(find.text(en.registrationTitle), findsOneWidget);
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
      expect(find.text(en.errInviteInvalid), findsOneWidget);
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
      expect(find.text(screenshotsLine('none')), findsOneWidget);
      await tester.tap(_button(requestScreenshotsLabel));
      await tester.pumpAndSettle();
      expect(fakes.upload.calls, contains('requestScreenshots $site'));
      expect(find.text(screenshotsLine('pending')), findsOneWidget);
      expect(_enabled(tester, _button(requestScreenshotsLabel)), isFalse);
    });

    testWidgets('an approved key shows the state and no request', (
      tester,
    ) async {
      await _openSettings(
        tester,
        _fakes(registered: true, screenshots: 'approved'),
      );
      expect(find.text(screenshotsLine('approved')), findsOneWidget);
      expect(_enabled(tester, _button(requestScreenshotsLabel)), isFalse);
    });
  });

  group('Website tab, key', () {
    Future<void> openNewKeyDialog(WidgetTester tester) async {
      await tapVisible(tester, _button(newKeyLabel));
      await tester.pumpAndSettle();
    }

    Finder dialogButton(String label) =>
        find.descendant(of: find.byType(AlertDialog), matching: _button(label));

    testWidgets('a refused code can be followed by another one', (
      tester,
    ) async {
      final fakes = _fakes();
      fakes.upload.registerError = const UploadException(
        'invite_invalid',
        'Not valid.',
        status: 403,
      );
      await _openSettings(tester, fakes);
      await tester.enterText(_field(inviteCodeLabel), 'nope');
      await tester.tap(_button(registerLabel));
      await tester.pumpAndSettle();
      expect(find.text(en.errInviteInvalid), findsOneWidget);
      expect(_enabled(tester, _button(registerLabel)), isTrue);

      fakes.upload.registerError = null;
      await tester.enterText(_field(inviteCodeLabel), 'GOOD1234');
      await tester.tap(_button(registerLabel));
      await tester.pumpAndSettle();
      expect(fakes.upload.registrations, [(site, 'nope'), (site, 'GOOD1234')]);
      expect(find.text(registeredText(site)), findsOneWidget);
      expect(find.text(en.errInviteInvalid), findsNothing);
    });

    testWidgets('Make a new key shows only when the app has a key', (
      tester,
    ) async {
      await _openSettings(tester, _fakes());
      expect(find.text(newKeyLabel), findsNothing);
      expect(find.byTooltip(copyKeyLabel), findsNothing);
    });

    testWidgets('Make a new key waits while an upload runs', (tester) async {
      final fakes = _fakes(
        settings: readySettings.copyWith(upload: true),
        registered: true,
      );
      fakes.upload.pendingSync = Completer<SyncReport>();
      await _openSettings(tester, fakes);
      expect(_enabled(tester, _button(newKeyLabel)), isTrue);
      await tester.tap(find.text(uploadNowLabel));
      await tester.pump();
      expect(_enabled(tester, _button(newKeyLabel)), isFalse);
      fakes.upload.pendingSync!.complete(
        const SyncReport(screenshots: 'none', characters: []),
      );
      await tester.pumpAndSettle();
      expect(_enabled(tester, _button(newKeyLabel)), isTrue);
    });

    testWidgets('Cancel in the dialog keeps the key', (tester) async {
      final fakes = _fakes(
        settings: readySettings.copyWith(upload: true),
        registered: true,
      );
      await _openSettings(tester, fakes);
      await openNewKeyDialog(tester);
      expect(find.text(en.newKeyTitle), findsOneWidget);
      expect(
        find.text(en.newKeyQuestionText('wowjourney.xyz')),
        findsOneWidget,
      );
      await tester.tap(dialogButton(cancelLabel));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(fakes.upload.calls, isNot(contains('replaceKey')));
      expect(find.text(fingerprintText('0123456789abcdef')), findsOneWidget);
      expect(find.text(registeredText(site)), findsOneWidget);
      expect(_uploadSwitch(tester).value, isTrue);
    });

    testWidgets('a new key starts unregistered with Upload off', (
      tester,
    ) async {
      final fakes = _fakes(
        settings: readySettings.copyWith(upload: true),
        registered: true,
      );
      await _openSettings(tester, fakes);
      await openNewKeyDialog(tester);
      await tester.tap(dialogButton(newKeyLabel));
      await tester.pumpAndSettle();

      expect(fakes.upload.calls, contains('replaceKey'));
      expect(find.text(fingerprintText('fedcba9876543210')), findsOneWidget);
      expect(find.text(notRegisteredText(site)), findsOneWidget);
      expect(_field(inviteCodeLabel), findsOneWidget);
      expect(fakes.store.saved.last.upload, isFalse);
      expect(_uploadSwitch(tester).value, isFalse);
      expect(_uploadSwitch(tester).onChanged, isNull);
      expect(find.text(en.newKeyDoneText), findsOneWidget);
    });

    testWidgets('a blocked key can be replaced, then registered again', (
      tester,
    ) async {
      final fakes = _fakes();
      fakes.upload.fingerprint = '0123456789abcdef';
      fakes.upload.registerError = const UploadException(
        'key_revoked',
        'Blocked.',
        status: 403,
      );
      await _openSettings(tester, fakes);
      await tester.enterText(_field(inviteCodeLabel), 'CODE1');
      await tester.tap(_button(registerLabel));
      await tester.pumpAndSettle();
      expect(find.text(keyRevokedText(site)), findsOneWidget);

      await openNewKeyDialog(tester);
      await tester.tap(dialogButton(newKeyLabel));
      await tester.pumpAndSettle();
      expect(find.text(keyRevokedText(site)), findsNothing);
      expect(find.text(fingerprintText('fedcba9876543210')), findsOneWidget);

      fakes.upload.registerError = null;
      await tester.enterText(_field(inviteCodeLabel), 'CODE2');
      await tester.tap(_button(registerLabel));
      await tester.pumpAndSettle();
      expect(fakes.upload.registrations.last, (site, 'CODE2'));
      expect(find.text(registeredText(site)), findsOneWidget);
    });

    testWidgets('a failed new key keeps the old key and says why', (
      tester,
    ) async {
      final fakes = _fakes(
        settings: readySettings.copyWith(upload: true),
        registered: true,
      );
      fakes.upload.replaceError = const UploadException(
        'key_not_replaced',
        'Could not write.',
      );
      await _openSettings(tester, fakes);
      await openNewKeyDialog(tester);
      await tester.tap(dialogButton(newKeyLabel));
      await tester.pumpAndSettle();

      expect(find.text(en.errKeyNotReplaced), findsOneWidget);
      expect(find.text(fingerprintText('0123456789abcdef')), findsOneWidget);
      expect(find.text(registeredText(site)), findsOneWidget);
      expect(_uploadSwitch(tester).value, isTrue);
      expect(find.text(en.newKeyDoneText), findsNothing);
    });

    testWidgets('Copy puts the fingerprint on the clipboard', (tester) async {
      final semantics = tester.ensureSemantics();
      final fakes = _fakes(registered: true);
      await _openSettings(tester, fakes);
      expect(
        find.widgetWithText(
          SelectableText,
          fingerprintText('0123456789abcdef'),
        ),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(en.copyKeySemantics), findsOneWidget);

      await tapVisible(tester, find.byTooltip(copyKeyLabel));
      await tester.pumpAndSettle();
      expect(fakes.copied, ['0123456789abcdef']);
      expect(find.text(keyCopiedText), findsOneWidget);
      semantics.dispose();
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

      expect(fakes.upload.syncs, [(site, p.join('/backups/WoW Journey', 'latest'))]);
      expect(fakes.upload.syncSelections, [
        {nandu.path},
      ]);
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
      expect(find.textContaining('clock of your computer'), findsOneWidget);
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
      expect(
        find.textContaining('did not accept the signature'),
        findsOneWidget,
      );
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
      expect(fakes.upload.syncSelections, [
        {nandu.path},
      ]);
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
      final fakes = _fakes(registered: true, characters: [nandu]);
      useWindow(tester, height: 2400);
      await pumpApp(tester, fakes);
      await openTab(tester, 'Website');
      await tester.tap(find.text(copyLinkLabel));
      await tester.pumpAndSettle();
      expect(fakes.copied, [nandu.url]);
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

  group('Website tab, characters to upload', () {
    Finder box(String name) => find.descendant(
      of: find.widgetWithText(CheckboxListTile, name),
      matching: find.byType(Checkbox),
    );

    bool ticked(WidgetTester tester, String name) =>
        tester.widget<Checkbox>(box(name)).value!;

    Future<void> open(
      WidgetTester tester,
      Fakes fakes, {
      double? height,
    }) async {
      useWindow(tester, height: height ?? 2400);
      await pumpApp(tester, fakes);
      await openTab(tester, 'Website');
    }

    testWidgets('lists every local character with its details and a box', (
      tester,
    ) async {
      final fakes = _fakes(
        registered: true,
        local: [localNandu, _local('rhea')],
        selected: {nandu.path},
      );
      await open(tester, fakes);
      expect(find.text(en.selectionTitle), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsNWidgets(2));
      expect(ticked(tester, 'nandu'), isTrue);
      expect(ticked(tester, 'rhea'), isFalse);
      expect(find.textContaining('Brumamar · Level 70'), findsOneWidget);
      expect(find.textContaining('Hunter'), findsOneWidget);
      expect(find.text(en.selectionNote), findsOneWidget);
      expect(find.text(en.selectionHint), findsNothing);
    });

    testWidgets('a character is not offered before the key is registered', (
      tester,
    ) async {
      await open(tester, _fakes());
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.text(en.selectionHint), findsNothing);
    });

    testWidgets('the list shows with Upload off too', (tester) async {
      await open(tester, _fakes(registered: true));
      expect(find.text(cardUploadOffText), findsOneWidget);
      expect(find.byType(CheckboxListTile), findsOneWidget);
    });

    testWidgets('only an uploaded character has a link, Copy and Remove', (
      tester,
    ) async {
      final fakes = _fakes(
        registered: true,
        characters: [nandu],
        local: [localNandu, _local('rhea')],
        selected: {nandu.path},
      );
      await open(tester, fakes);
      expect(find.text(nandu.url), findsOneWidget);
      expect(find.text(copyLinkLabel), findsOneWidget);
      expect(find.text(removeFromWebsiteLabel), findsOneWidget);
    });

    testWidgets('a character on the site that the folder lacks is listed', (
      tester,
    ) async {
      final fakes = _fakes(registered: true, characters: [nandu], local: []);
      await open(tester, fakes);
      expect(find.byType(CheckboxListTile), findsNothing);
      expect(find.text(en.noCharacters), findsOneWidget);
      expect(find.text(nandu.url), findsOneWidget);
      expect(find.text(removeFromWebsiteLabel), findsOneWidget);
    });

    testWidgets('with nothing selected: the hint, and Upload now is off', (
      tester,
    ) async {
      final fakes = _fakes(
        settings: readySettings.copyWith(upload: true),
        registered: true,
        selected: {},
      );
      await open(tester, fakes);
      expect(find.text(en.selectionHint), findsOneWidget);
      expect(_enabled(tester, _button(uploadNowLabel)), isFalse);

      await tester.tap(box('nandu'));
      await tester.pumpAndSettle();
      expect(find.text(en.selectionHint), findsNothing);
      expect(_enabled(tester, _button(uploadNowLabel)), isTrue);
    });

    testWidgets('ticking and unticking save the choice and delete nothing', (
      tester,
    ) async {
      final fakes = _fakes(
        registered: true,
        local: [localNandu, _local('rhea')],
        selected: {},
      );
      await open(tester, fakes);
      await tester.tap(box('rhea'));
      await tester.pumpAndSettle();
      expect(ticked(tester, 'rhea'), isTrue);
      expect(fakes.upload.selections[site], {'wow/eu/brumamar/rhea'});
      await tester.tap(box('rhea'));
      await tester.pumpAndSettle();
      expect(ticked(tester, 'rhea'), isFalse);
      expect(fakes.upload.selections[site], isEmpty);
      expect(fakes.upload.deletions, isEmpty);
    });

    testWidgets('Select all and Select none', (tester) async {
      final fakes = _fakes(
        registered: true,
        local: [localNandu, _local('rhea'), _local('sol')],
        selected: {nandu.path},
      );
      await open(tester, fakes);
      expect(_enabled(tester, _button(en.selectAllLabel)), isTrue);
      expect(_enabled(tester, _button(en.selectNoneLabel)), isTrue);

      await tester.tap(_button(en.selectAllLabel));
      await tester.pumpAndSettle();
      for (final name in ['nandu', 'rhea', 'sol']) {
        expect(ticked(tester, name), isTrue);
      }
      expect(_enabled(tester, _button(en.selectAllLabel)), isFalse);
      expect(fakes.upload.selections[site], hasLength(3));

      await tester.tap(_button(en.selectNoneLabel));
      await tester.pumpAndSettle();
      for (final name in ['nandu', 'rhea', 'sol']) {
        expect(ticked(tester, name), isFalse);
      }
      expect(_enabled(tester, _button(en.selectNoneLabel)), isFalse);
      expect(fakes.upload.selections[site], isEmpty);
      expect(find.text(en.selectionHint), findsOneWidget);
    });

    testWidgets('Upload now sends only the ticked characters', (tester) async {
      final fakes = _fakes(
        settings: readySettings.copyWith(upload: true),
        registered: true,
        local: [localNandu, _local('rhea')],
        selected: {'wow/eu/brumamar/rhea'},
      );
      await open(tester, fakes);
      await tester.tap(find.text(uploadNowLabel));
      await tester.pumpAndSettle();
      expect(fakes.upload.syncSelections, [
        {'wow/eu/brumamar/rhea'},
      ]);
    });

    testWidgets('a character gathered later appears unticked', (tester) async {
      final fakes = _fakes(
        settings: readySettings.copyWith(upload: true),
        registered: true,
      );
      await open(tester, fakes);
      fakes.gather.snapshot = BackupSnapshot(
        characters: [localNandu, _local('rhea')],
      );
      await openTab(tester, 'Overview');
      await tester.tap(find.text('Gather now'));
      await tester.pumpAndSettle();
      await openTab(tester, 'Website');
      expect(ticked(tester, 'nandu'), isTrue);
      expect(ticked(tester, 'rhea'), isFalse);
      expect(fakes.upload.syncSelections.last, {nandu.path});
    });

    testWidgets('Remove from website unticks the character', (tester) async {
      final fakes = _fakes(registered: true, characters: [nandu]);
      await open(tester, fakes);
      expect(ticked(tester, 'nandu'), isTrue);
      await tester.tap(find.text(removeFromWebsiteLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text(removeLabel));
      await tester.pumpAndSettle();
      expect(ticked(tester, 'nandu'), isFalse);
      expect(find.text(nandu.url), findsNothing);
      expect(fakes.upload.selections[site], isEmpty);
      expect(find.text(removedText('nandu')), findsOneWidget);
    });

    testWidgets('25 characters scroll in the list and do not overflow', (
      tester,
    ) async {
      final names = [
        for (var i = 1; i <= 25; i++) 'char${i.toString().padLeft(2, '0')}',
      ];
      final fakes = _fakes(
        settings: readySettings.copyWith(upload: true),
        registered: true,
        characters: [
          for (final n in names.take(5))
            RemoteCharacter(
              path: 'wow/eu/brumamar/$n',
              url: '$site/wow/eu/brumamar/$n/',
              guid: 'Player-1-$n',
              steps: 1,
              updated: 1,
            ),
        ],
        local: [for (final n in names) _local(n)],
        selected: {for (final n in names.take(5)) 'wow/eu/brumamar/$n'},
      );
      await open(tester, fakes, height: 700);
      expect(tester.takeException(), isNull);
      expect(find.text('char25'), findsNothing);

      await tester.dragUntilVisible(
        find.text('char25'),
        find.descendant(
          of: find.byType(Card).first,
          matching: find.byType(Scrollable),
        ),
        const Offset(0, -200),
      );
      await tester.pumpAndSettle();
      expect(find.text('char25'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a narrow window with large text does not overflow', (
      tester,
    ) async {
      final fakes = _fakes(
        registered: true,
        characters: [nandu],
        local: [localNandu, _local('rhea')],
      );
      useWindow(tester, width: 520, height: 800, textScale: 1.5);
      await pumpApp(tester, fakes);
      await openTab(tester, 'Website');
      expect(tester.takeException(), isNull);
    });
  });
}
