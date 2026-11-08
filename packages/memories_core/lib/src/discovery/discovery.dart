/// Finds the WoW flavor folders on this system and checks a folder that the
/// user picked. It only reads; it never writes a file.
library;

import 'dart:io';

import 'candidates.dart';

/// One game version folder, such as `World of Warcraft/_retail_`.
class WowFolder {
  const WowFolder({
    required this.installDir,
    required this.flavorDir,
    required this.flavor,
    required this.hasMemoriesData,
  });

  /// The World of Warcraft folder that holds [flavorDir].
  final String installDir;

  /// The folder that holds `WTF/Account`; a gather reads this one.
  final String flavorDir;

  /// The name of [flavorDir], such as `_retail_`.
  final String flavor;

  /// Whether an account in it has a Memories saved file.
  final bool hasMemoriesData;

  @override
  bool operator ==(Object other) =>
      other is WowFolder &&
      other.installDir == installDir &&
      other.flavorDir == flavorDir &&
      other.flavor == flavor &&
      other.hasMemoriesData == hasMemoriesData;

  @override
  int get hashCode =>
      Object.hash(installDir, flavorDir, flavor, hasMemoriesData);

  @override
  String toString() =>
      'WowFolder($flavorDir, install: $installDir, flavor: $flavor, '
      'memories: $hasMemoriesData)';
}

/// The answer of [validateFlavorDir] for a picked folder.
sealed class FlavorCheck {
  const FlavorCheck();

  /// What happened and what to do, in plain English.
  String get message;
}

/// The folder is a flavor folder; a gather can read it.
class Valid extends FlavorCheck {
  const Valid(this.folder);

  final WowFolder folder;

  String get flavorDir => folder.flavorDir;

  @override
  String get message => folder.hasMemoriesData
      ? 'This WoW folder is ready.'
      : 'This WoW folder is ready, but it has no Memories data yet. '
            'Play with the Memories addons on. '
            'The game saves its files when you log out or type /reload.';
}

/// The folder has no `WTF/Account` folder and no flavor folder.
class NoWtf extends FlavorCheck {
  const NoWtf(this.path);

  final String path;

  @override
  String get message =>
      'This folder is not a WoW game folder. It has no WTF/Account folder. '
      'Pick the folder of one game version inside your World of Warcraft '
      'folder, such as _retail_.';
}

/// The folder is the World of Warcraft folder; it holds [flavors].
class IsInstallFolder extends FlavorCheck {
  const IsInstallFolder(this.path, this.flavors);

  final String path;

  /// The flavor folders in it, in the order of [discoverWow].
  final List<WowFolder> flavors;

  @override
  String get message {
    final names = flavors.map((f) => f.flavor).join(', ');
    return flavors.length == 1
        ? 'This is the World of Warcraft folder. '
              'It holds one game version: $names. Pick that folder.'
        : 'This is the World of Warcraft folder. '
              'It holds ${flavors.length} game versions: $names. '
              'Pick one of them.';
  }
}

/// The path is a file, or nothing is there.
class NotADirectory extends FlavorCheck {
  const NotADirectory(this.path);

  final String path;

  @override
  String get message =>
      'This is not a folder, or it does not exist any more. Pick a folder.';
}

/// The folder cannot be listed.
class NotReadable extends FlavorCheck {
  const NotReadable(this.path);

  final String path;

  @override
  String get message =>
      'This folder, or a folder in it, cannot be read. '
      'Check that your user may open it, then pick it again.';
}

/// The flavor folders of every known install folder on this system, the
/// ones with Memories data first, then the ones named like `forever`. A folder
/// reached by two paths is listed once. It reads the disk synchronously, so a
/// UI calls it off its main isolate.
Future<List<WowFolder>> discoverWow({Environment? environment}) async {
  final env = environment ?? const Environment();
  return _unique(env, [
    for (final install in await installCandidates(env))
      ..._flavorsIn(env, install),
  ]);
}

/// The sorted folders of [found], each resolved path once.
List<WowFolder> _unique(Environment env, List<(WowFolder, String)> found) {
  final seen = <String>{};
  return sortFolders([
    for (final (folder, resolved) in found)
      if (seen.add(_key(env, resolved))) folder,
  ]);
}

/// Tells whether a folder that the user picked can be gathered.
FlavorCheck validateFlavorDir(String path, {Environment? environment}) {
  final env = environment ?? const Environment();
  final ctx = env.pathContext;
  final dir = ctx.normalize(ctx.absolute(path));
  final root = env.resolve(dir);
  if (root == null || !env.isDirectory(dir)) return NotADirectory(dir);
  try {
    env.listDirectories(dir);
    final own = _inspect(env, root, dir, ctx.dirname(dir));
    if (own != null) return Valid(own);
  } on FileSystemException {
    return NotReadable(dir);
  }
  final flavors = _unique(env, _flavorsIn(env, dir));
  return flavors.isEmpty ? NoWtf(dir) : IsInstallFolder(dir, flavors);
}

/// Sorts [folders] with Memories data first, then the names that hold
/// `forever`, and keeps the given order between equal ones.
List<WowFolder> sortFolders(List<WowFolder> folders) {
  int rank(WowFolder f) =>
      (f.hasMemoriesData ? 0 : 2) +
      (f.flavor.toLowerCase().contains('forever') ? 0 : 1);
  final indexed = folders.indexed.toList()
    ..sort((a, b) {
      final c = rank(a.$2).compareTo(rank(b.$2));
      return c != 0 ? c : a.$1.compareTo(b.$1);
    });
  return [for (final (_, f) in indexed) f];
}

/// The flavor folders in [install], each with its resolved path. A folder
/// that cannot be read is left out.
List<(WowFolder, String)> _flavorsIn(Environment env, String install) {
  final ctx = env.pathContext;
  final root = env.resolve(install);
  if (root == null || !env.isDirectory(install)) return [];
  final out = <(WowFolder, String)>[];
  final List<String> children;
  try {
    children = env.listDirectories(install)..sort();
  } on FileSystemException {
    return [];
  }
  for (final child in children) {
    if (!flavorName.hasMatch(ctx.basename(child))) continue;
    final resolved = _resolveInside(env, root, child);
    if (resolved == null) continue;
    try {
      // The flavor folder is the root, as in validateFlavorDir, so that a
      // folder offered here is never refused when the user picks it.
      final folder = _inspect(env, resolved, child, install);
      if (folder != null) out.add((folder, resolved));
    } on FileSystemException {
      continue;
    }
  }
  return out;
}

/// The [WowFolder] of [dir] when it holds `WTF/Account` inside [root], else
/// null. It throws a [FileSystemException] when the accounts cannot be
/// listed.
WowFolder? _inspect(Environment env, String root, String dir, String install) {
  final ctx = env.pathContext;
  final accounts = ctx.join(dir, 'WTF', 'Account');
  if (!env.isDirectory(accounts) ||
      _resolveInside(env, root, accounts) == null) {
    return null;
  }
  var memories = false;
  for (final account in env.listDirectories(accounts)) {
    // A gather skips linked accounts and a linked Memories.lua.
    if (env.isLink(account)) continue;
    final file = ctx.join(account, 'SavedVariables', 'Memories.lua');
    if (env.isFile(file) && _resolveInside(env, root, file) != null) {
      memories = true;
      break;
    }
  }
  return WowFolder(
    installDir: install,
    flavorDir: dir,
    flavor: ctx.basename(dir),
    hasMemoriesData: memories,
  );
}

/// The resolved [path] when it stays in [root], so that a link out of the
/// folder that is looked at is never followed; else null.
String? _resolveInside(Environment env, String root, String path) {
  final resolved = env.resolve(path);
  if (resolved == null) return null;
  final ctx = env.pathContext;
  final a = _key(env, resolved);
  final b = _key(env, root);
  return ctx.equals(a, b) || ctx.isWithin(b, a) ? resolved : null;
}

/// The form of a resolved path that two spellings of one folder share. The
/// file systems of Windows and macOS ignore case by default.
String _key(Environment env, String resolved) {
  final n = env.pathContext.normalize(resolved);
  return env.operatingSystem == 'linux' ? n : n.toLowerCase();
}
