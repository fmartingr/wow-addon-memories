/// The memories-upload command line tool.
library;

import 'dart:io';

import 'package:args/args.dart';
import 'package:http/http.dart' as http;

import '../cli_flags.dart';
import 'client.dart';
import 'key.dart';
import 'site.dart';
import 'state.dart';
import 'sync.dart';

/// The usage line of the tool.
const String usage =
    'usage: memories-upload --site URL [--key FILE] [--state FILE] '
    '[--latest DIR] [--invite CODE] [--delete PATH] [--request-screenshots]';

const Set<String> _valued = {
  'site',
  'key',
  'state',
  'latest',
  'invite',
  'delete',
};

ArgParser _parser() => ArgParser()
  ..addOption(
    'site',
    help: 'website address, for example https://wowjourney.xyz (required)',
    defaultsTo: '',
  )
  ..addOption(
    'key',
    help: 'key file; made when it is missing',
    defaultsTo: './upload-key.json',
  )
  ..addOption(
    'state',
    help: 'file where the upload remembers what it sent',
    defaultsTo: './upload-state.json',
  )
  ..addOption(
    'latest',
    help: 'latest/ folder of a gather; its changed characters are uploaded',
    defaultsTo: '',
  )
  ..addOption(
    'invite',
    help: 'invite code; registers the key before the other actions',
    defaultsTo: '',
  )
  ..addOption(
    'delete',
    help: 'remove the character at this path, for example wow/eu/realm/name',
    defaultsTo: '',
  )
  ..addFlag(
    'request-screenshots',
    negatable: false,
    help: 'ask the website admin for the approval to upload screenshots',
  )
  ..addFlag('help', abbr: 'h', negatable: false, help: 'show this help');

/// Runs the tool with [args] and returns its exit code: 0 when it passed, 1
/// for an error during the run, 2 for an error in the arguments. [httpClient]
/// and [now] let a test replace the network and the clock.
Future<int> runMemoriesUpload(
  List<String> args, {
  required StringSink out,
  required StringSink err,
  http.Client? httpClient,
  DateTime Function()? now,
}) async {
  final parser = _parser();
  final ArgResults opts;
  try {
    opts = parser.parse(longFlags(args, _valued));
  } on ArgParserException catch (e) {
    err
      ..writeln(flagError(e))
      ..writeln('Usage of memories-upload:')
      ..writeln(parser.usage);
    return 2;
  }
  if (opts.flag('help')) {
    err
      ..writeln('Usage of memories-upload:')
      ..writeln(parser.usage);
    return 0;
  }
  final keyPath = opts.option('key')!;
  final statePath = opts.option('state')!;
  final latestPath = opts.option('latest')!;
  final invite = opts.option('invite')!;
  final deletePath = opts.option('delete')!;
  if (opts.option('site')!.isEmpty ||
      keyPath.isEmpty ||
      statePath.isEmpty ||
      opts.rest.isNotEmpty) {
    err.writeln(usage);
    return 2;
  }
  final Uri site;
  try {
    site = parseSite(opts.option('site')!);
  } on FormatException catch (e) {
    err.writeln('memories-upload: usage: ${e.message}');
    return 2;
  }
  if (deletePath.isNotEmpty && !isCharacterPath(deletePath)) {
    err.writeln(
      'memories-upload: usage: --delete needs a character path like '
      'wow/eu/realm-name/character-name.',
    );
    return 2;
  }

  final UploadKey key;
  try {
    key = _loadOrMakeKey(File(keyPath), out);
  } on UploadKeyException catch (e) {
    err.writeln('memories-upload: $e');
    return 1;
  } on FileSystemException catch (e) {
    err.writeln(
      'memories-upload: could not read or write the key file '
      '$keyPath: ${e.osError?.message ?? e.message}.',
    );
    return 1;
  }

  final stateFile = File(statePath);
  final UploadState state;
  try {
    state = UploadState.load(stateFile);
  } on FileSystemException catch (e) {
    err.writeln(
      'memories-upload: could not read the state file '
      '$statePath: ${e.osError?.message ?? e.message}.',
    );
    return 1;
  }
  final warning = state.warning;
  if (warning != null) err.writeln('memories-upload: warning: $warning');

  final client = UploadClient(site, key, client: httpClient, clock: now);
  final run = _Run(client, state.site(site), state, out, err);
  try {
    await run.all(
      invite: invite,
      latest: latestPath.isEmpty ? null : Directory(latestPath),
      delete: deletePath.isEmpty ? null : deletePath,
      requestScreenshots: opts.flag('request-screenshots'),
    );
  } finally {
    client.close();
    try {
      state.save(stateFile);
    } on FileSystemException catch (e) {
      err.writeln(
        'memories-upload: could not write the state file '
        '$statePath: ${e.osError?.message ?? e.message}.',
      );
      run.failed = true;
    }
  }
  return run.failed ? 1 : 0;
}

class _Run {
  _Run(this.client, this.site, this.state, this.out, this.err);

  final UploadClient client;
  final SiteState site;
  final UploadState state;
  final StringSink out;
  final StringSink err;
  bool failed = false;

  Future<void> all({
    required String invite,
    required Directory? latest,
    required String? delete,
    required bool requestScreenshots,
  }) async {
    if (!site.registered || invite.isNotEmpty) {
      if (!await _step(() => _register(invite))) return;
    }
    if (latest != null) await _step(() => _sync(latest));
    if (delete != null) await _step(() => _delete(delete));
    if (requestScreenshots) await _step(_requestScreenshots);
  }

  /// Runs one action. A failure is printed and counted, and the next action
  /// still runs, except that a failed registration ends the run.
  Future<bool> _step(Future<void> Function() action) async {
    try {
      await action();
      return true;
    } on UploadException catch (e) {
      failed = true;
      if (e.code == 'not_registered') site.registered = false;
      _printError(e);
      return false;
    }
  }

  void _printError(UploadException e) {
    err.writeln('memories-upload: ${e.message}');
    for (final p in e.problems) {
      err.writeln('  $p');
    }
    final wait = e.retryAfter;
    if (wait != null) err.writeln('  Retry-After: $wait seconds.');
  }

  Future<void> _register(String invite) async {
    final created = await client.register(
      invite: invite.isEmpty ? null : invite,
    );
    site.registered = true;
    out.writeln(
      created
          ? 'Registered this key on ${client.site}.'
          : 'This key is already registered on ${client.site}.',
    );
  }

  Future<void> _sync(Directory latest) async {
    final report = await syncLatest(latest, client, state);
    var uploaded = 0;
    var unchanged = 0;
    var failures = 0;
    UploadException? shown;
    for (final c in report.characters) {
      final name = c.path.isEmpty ? c.id : c.path;
      switch (c.status) {
        case SyncStatus.uploaded:
          uploaded++;
          final o = c.outcome!;
          out.writeln(
            'uploaded $name: ${o.steps} steps, ${o.added} new. ${o.url}',
          );
        case SyncStatus.unchanged:
          unchanged++;
          out.writeln('unchanged $name');
        case SyncStatus.failed:
          failures++;
          final e = c.error!;
          if (e.code == 'not_registered') site.registered = false;
          if (identical(e, shown)) {
            err.writeln('not sent $name: the run stopped at the error above.');
          } else {
            err.writeln('failed $name:');
            _printError(e);
            shown = e;
          }
      }
      if (c.shots.uploaded > 0 || c.shots.unchanged > 0) {
        out.writeln(
          'screenshots $name: ${c.shots.uploaded} uploaded, '
          '${c.shots.unchanged} unchanged',
        );
      }
      for (final e in c.shots.errors) {
        err.writeln('screenshot failed $name: $e');
      }
      // A screenshot failure that stops the run is the error above for every
      // character after it, so its Retry-After is printed here, once.
      final shotStop = c.shots.stop;
      if (shotStop != null && !identical(shotStop, shown)) {
        if (shotStop.code == 'not_registered') site.registered = false;
        final wait = shotStop.retryAfter;
        if (wait != null) err.writeln('  Retry-After: $wait seconds.');
        shown = shotStop;
      }
    }
    if (!report.screenshotsApprovedState) {
      out.writeln(
        report.screenshots == 'pending'
            ? 'Screenshots were not uploaded: the website admin has not '
                  'answered the screenshot request of this key yet.'
            : 'Screenshots were not uploaded: the screenshot state of this '
                  'key is "${report.screenshots}". Use --request-screenshots '
                  'to ask for approval.',
      );
    }
    out.writeln(
      'Done: $uploaded uploaded, $unchanged unchanged, $failures failed.',
    );
    if (report.failed) failed = true;
  }

  Future<void> _delete(String path) async {
    await client.deleteCharacter(path);
    site.forget(path);
    out.writeln('Removed $path from ${client.site}.');
  }

  Future<void> _requestScreenshots() async {
    final result = await client.requestScreenshots();
    out.writeln('Screenshot state of this key: $result.');
  }
}

UploadKey _loadOrMakeKey(File file, StringSink out) {
  if (file.existsSync()) return UploadKey.load(file);
  final key = UploadKey.generate()..save(file);
  out.writeln(
    'Made a new key in ${file.path} (fingerprint ${key.fingerprint}). Keep '
    'this file: it is the only proof that your characters are yours.',
  );
  return key;
}
