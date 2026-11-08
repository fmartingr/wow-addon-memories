import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:memories_core/memories_core.dart';
import 'package:wow_journey/src/ui/messages.dart';
import 'package:wow_journey/src/version.dart';

void main() {
  group('issueText', () {
    for (final code in GatherIssueCode.values) {
      test('$code has plain text', () {
        final text = issueText(code);
        expect(text, isNotEmpty);
        expect(text, endsWith('.'));
        expect(text, isNot(contains('--')));
        expect(text, isNot(contains('Exception')));
        expect(text, isNot(contains(r'$')));
        expect(text, isNot(contains(code.name)));
        for (final sentence in text.split('. ')) {
          expect(
            sentence.split(' ').length,
            lessThanOrEqualTo(20),
            reason: 'short sentences: "$sentence"',
          );
        }
      });
    }

    test('no data tells the player what to do', () {
      expect(
        issueText(GatherIssueCode.noData),
        'No Memories data yet. Play with the Memories addons on, then log out.',
      );
    });
  });

  test('the fixes are the ones a player can do', () {
    expect(issueFix(GatherIssueCode.noWtf), IssueFix.chooseWowFolder);
    expect(issueFix(GatherIssueCode.notWritable), IssueFix.chooseBackupFolder);
    expect(issueFix(GatherIssueCode.overlap), IssueFix.chooseBackupFolder);
    expect(issueFix(GatherIssueCode.lockHeld), IssueFix.tryAgain);
    expect(issueFix(GatherIssueCode.ioError), IssueFix.tryAgain);
    expect(issueFix(GatherIssueCode.badIndex), IssueFix.openLatest);
    expect(issueFix(GatherIssueCode.noData), isNull);
    expect(IssueFix.chooseWowFolder.label, 'Choose folder');
    expect(IssueFix.tryAgain.label, 'Try again');
  });

  test('formatSize', () {
    expect(formatSize(0), '0 bytes');
    expect(formatSize(1023), '1023 bytes');
    expect(formatSize(1536), '1.5 KB');
    expect(formatSize(5 * 1024 * 1024), '5.0 MB');
    expect(formatSize(3 * 1024 * 1024 * 1024), '3.0 GB');
  });

  test('formatTime shows the date only on another day', () {
    final now = DateTime(2026, 11, 8, 20);
    expect(formatTime(DateTime(2026, 11, 8, 14, 32), now), '14:32');
    expect(formatTime(DateTime(2026, 11, 7, 9, 5), now), '2026-11-07 09:05');
  });

  test('className', () {
    expect(className('HUNTER'), 'Hunter');
    expect(className('DEATHKNIGHT'), 'Death Knight');
    expect(className(''), '');
  });

  test('the app version is the version of pubspec.yaml', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version: ([^+\s]+)',
      multiLine: true,
    ).firstMatch(pubspec)![1];
    expect(appVersion, version);
  });
}
