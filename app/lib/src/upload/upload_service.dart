/// The upload of the journey to a website, behind an interface so that tests
/// pass a fake. The app imports no HTTP code: `memories_core` holds it.
library;

import 'dart:io';
import 'dart:isolate';

import 'package:memories_core/memories_core.dart' as core;
import 'package:path/path.dart' as p;

/// What the app knows about its key on one website, with no request.
typedef SiteStatus = ({bool registered, String? fingerprint});

/// Talks to a website. Each method takes the website address as the user
/// wrote it, and throws an [core.UploadException] with a plain message when it
/// cannot do its work.
abstract interface class UploadService {
  /// Whether this key registered on [site], and the key fingerprint (null
  /// until the app made a key).
  Future<SiteStatus> status(String site);

  /// Asks [site] about itself.
  Future<core.SiteInfo> info(String site);

  /// Registers the key on [site], with the [invite] code when it has one.
  /// Makes the key on the first call.
  Future<void> register(String site, String? invite);

  /// The characters that [site] holds for the key, and the screenshot state.
  Future<core.MeInfo> me(String site);

  /// Uploads the changed characters of the `latest/` folder [latestDir].
  /// A character removed with [delete] is skipped, unless [resendRemoved] is
  /// true: then every removed character is sent again.
  Future<core.SyncReport> sync(
    String site,
    String latestDir, {
    bool resendRemoved = false,
  });

  /// Removes the character at [path] from [site]. The next [sync] skips it
  /// until a sync with `resendRemoved`.
  Future<void> delete(String site, String path);

  /// Asks [site] to approve screenshots. Returns the new state.
  Future<String> requestScreenshots(String site);
}

/// The upload of `memories_core`. The key is `<support>/upload-key.json` and
/// the state is `<support>/upload-state.json`.
class CoreUploadService implements UploadService {
  CoreUploadService(this.supportDir);

  /// The folder where the app keeps its own files.
  final Future<String> Function() supportDir;

  /// The end of the last write of the state file. A sync loads the state at
  /// its start and saves it at its end, so a register in between would be
  /// lost; each writer waits for the one before it.
  Future<void> _stateWrites = Future.value();

  Future<T> _serialState<T>(Future<T> Function() run) {
    final result = _stateWrites.then((_) => run());
    _stateWrites = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<({String key, String state})> _files() async {
    final dir = await supportDir();
    return (
      key: p.join(dir, 'upload-key.json'),
      state: p.join(dir, 'upload-state.json'),
    );
  }

  @override
  Future<SiteStatus> status(String site) async {
    final uri = _parse(site);
    final files = await _files();
    final key = _loadKey(files.key, MissingKey.none);
    return (
      registered: core.UploadState.load(File(files.state)).site(uri).registered,
      fingerprint: key?.fingerprint,
    );
  }

  @override
  Future<core.SiteInfo> info(String site) async {
    // The request is not signed, so a damaged key file never blocks a check.
    final client = core.UploadClient(_parse(site), core.UploadKey.generate());
    try {
      return await client.info();
    } finally {
      client.close();
    }
  }

  @override
  Future<void> register(String site, String? invite) =>
      _withClient(site, MissingKey.create, (client, files) async {
        await client.register(invite: invite);
        await _serialState(() async {
          final state = core.UploadState.load(File(files.state));
          state.site(client.site).registered = true;
          state.save(File(files.state));
        });
      });

  @override
  Future<core.MeInfo> me(String site) =>
      _withClient(site, MissingKey.fail, (client, files) => client.me());

  @override
  Future<core.SyncReport> sync(
    String site,
    String latestDir, {
    bool resendRemoved = false,
  }) async {
    final uri = _parse(site);
    final files = await _files();
    // Fail here, in this isolate, so a missing key never reaches the worker.
    _loadKey(files.key, MissingKey.fail);
    try {
      return await _serialState(
        () => _syncInIsolate(
          uri.toString(),
          latestDir,
          files.key,
          files.state,
          resendRemoved,
        ),
      );
    } on RemoteError {
      throw const core.UploadException(
        'failed',
        'The upload stopped because of a problem inside the app. Try again '
            'after the next gather.',
      );
    }
  }

  @override
  Future<void> delete(String site, String path) =>
      _withClient(site, MissingKey.fail, (client, files) async {
        try {
          await client.deleteCharacter(path);
        } on core.UploadException catch (e) {
          // 404: the site does not hold it, so it stays removed all the same.
          if (e.code == 'not_found') {
            await _markRemoved(client.site, path, files.state);
          }
          rethrow;
        }
        await _markRemoved(client.site, path, files.state);
      });

  /// Keeps an automatic sync from sending the character at [path] again.
  Future<void> _markRemoved(Uri site, String path, String statePath) =>
      _serialState(() async {
        try {
          final state = core.UploadState.load(File(statePath));
          state.site(site).markRemoved(path);
          state.save(File(statePath));
        } on FileSystemException {
          throw core.UploadException(
            'bad_state',
            'The character was removed from the website, but the app could '
                'not save that in $statePath, so the next gather may upload it '
                'again. Check that the folder can be written to.',
          );
        }
      });

  @override
  Future<String> requestScreenshots(String site) => _withClient(
    site,
    MissingKey.fail,
    (client, files) => client.requestScreenshots(),
  );

  Future<T> _withClient<T>(
    String site,
    MissingKey missing,
    Future<T> Function(core.UploadClient client, ({String key, String state}))
    run,
  ) async {
    final uri = _parse(site);
    final files = await _files();
    final client = core.UploadClient(uri, _loadKey(files.key, missing)!);
    try {
      return await run(client, files);
    } finally {
      client.close();
    }
  }
}

/// What to do when the key file does not exist.
enum MissingKey {
  /// Return null.
  none,

  /// Make the key and save it.
  create,

  /// Throw: the app has no key to sign with yet.
  fail,
}

core.UploadKey? _loadKey(String path, MissingKey missing) {
  final file = File(path);
  // An unreadable file is never taken for a missing one: a new key would
  // replace it, and the characters of the old key would be lost.
  if (file.existsSync()) {
    try {
      return core.UploadKey.load(file);
    } on core.UploadKeyException catch (e) {
      throw core.UploadException('bad_key', e.message);
    } on FileSystemException {
      throw core.UploadException(
        'bad_key',
        'The key file $path cannot be read. Check its permissions.',
      );
    }
  }
  switch (missing) {
    case MissingKey.none:
      return null;
    case MissingKey.create:
      final key = core.UploadKey.generate();
      try {
        key.save(file);
      } on core.UploadKeyException catch (e) {
        throw core.UploadException('bad_key', e.message);
      } on FileSystemException {
        throw core.UploadException(
          'bad_key',
          'The key file $path cannot be written. Check that the folder has '
              'free space and can be written to.',
        );
      }
      return key;
    case MissingKey.fail:
      throw const core.UploadException(
        'not_registered',
        'This app has no key for the website yet.',
      );
  }
}

Uri _parse(String site) {
  try {
    return core.parseSite(site);
  } on FormatException catch (e) {
    throw core.UploadException('bad_site', e.message);
  }
}

/// Runs [syncInto] on a new isolate. A top-level function, so the closure sent
/// to the isolate holds only these strings.
Future<core.SyncReport> _syncInIsolate(
  String site,
  String latestDir,
  String keyPath,
  String statePath,
  bool resendRemoved,
) => Isolate.run(
  () => syncInto(
    site,
    latestDir,
    keyPath,
    statePath,
    resendRemoved: resendRemoved,
  ),
);

/// Uploads [latestDir] to [site] and saves the state. It runs on any isolate,
/// and only strings go in.
Future<core.SyncReport> syncInto(
  String site,
  String latestDir,
  String keyPath,
  String statePath, {
  bool resendRemoved = false,
}) async {
  final uri = _parse(site);
  final client = core.UploadClient(uri, _loadKey(keyPath, MissingKey.fail)!);
  final state = core.UploadState.load(File(statePath));
  try {
    return await core.syncLatest(
      Directory(latestDir),
      client,
      state,
      resendRemoved: resendRemoved,
    );
  } finally {
    client.close();
    try {
      state.save(File(statePath));
    } on FileSystemException {
      // The next sync sends what the file does not remember again; the
      // website merges it with no change.
    }
  }
}
