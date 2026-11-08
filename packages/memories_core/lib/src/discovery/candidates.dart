/// The places where a WoW install folder may be, for each system, and the
/// system access that discovery uses to look at them.
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

/// The exit code and the output of a finished process.
typedef ProcessOutput = ({int exitCode, String stdout});

/// The system that discovery reads: the platform, the environment, processes
/// and the file system. The default reads `dart:io`; tests override it to
/// pose as another system.
class Environment {
  const Environment();

  /// The name of the system, as `Platform.operatingSystem` gives it.
  String get operatingSystem => Platform.operatingSystem;

  /// The environment variables.
  Map<String, String> get env => Platform.environment;

  /// The home folder of the user, or null when the environment has none.
  String? get home {
    final value = env[operatingSystem == 'windows' ? 'USERPROFILE' : 'HOME'];
    return value == null || value.isEmpty ? null : value;
  }

  /// The path rules of [operatingSystem]. On this system they also know the
  /// current folder.
  p.Context get pathContext => operatingSystem == Platform.operatingSystem
      ? p.context
      : operatingSystem == 'windows'
      ? p.windows
      : p.posix;

  /// Runs a command, or returns null when it cannot start, does not end in
  /// time or prints text that cannot be decoded. A command that does not end
  /// in time is killed.
  Future<ProcessOutput?> runProcess(
    String executable,
    List<String> arguments,
  ) async {
    final Process process;
    try {
      process = await Process.start(executable, arguments);
    } on ProcessException {
      return null;
    }
    final out = process.stdout.transform(systemEncoding.decoder).join();
    process.stderr.drain<void>().ignore();
    try {
      final (code, text) = await (
        process.exitCode,
        out,
      ).wait.timeout(const Duration(seconds: 10));
      return (exitCode: code, stdout: text);
    } on TimeoutException {
      process.kill();
      return null;
    } on ParallelWaitError<Object?, Object?> {
      return null;
    }
  }

  /// Whether a file or a folder is at [path]. A broken link is not.
  bool exists(String path) =>
      FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;

  /// Whether [path] is a regular file, not a link, as a gather reads it.
  bool isFile(String path) =>
      FileSystemEntity.typeSync(path, followLinks: false) ==
      FileSystemEntityType.file;

  /// Whether [path] is a link.
  bool isLink(String path) => FileSystemEntity.isLinkSync(path);

  /// Whether [path] is a folder, or a link to one.
  bool isDirectory(String path) => FileSystemEntity.isDirectorySync(path);

  /// The paths of the folders in [path], links to folders included. It
  /// throws a [FileSystemException] when [path] cannot be listed.
  List<String> listDirectories(String path) => [
    for (final e in Directory(path).listSync())
      if (e is Directory) e.path,
  ];

  /// The absolute path of [path] with every link resolved, or null when it
  /// does not exist or a link in it is broken.
  String? resolve(String path) {
    try {
      return File(path).resolveSymbolicLinksSync();
    } on FileSystemException {
      return null;
    }
  }
}

// HKLM...\World of Warcraft InstallPath points into a flavor folder. Community
// source (the PSElvUI script), unverified on a current install.
const List<String> _registryKeys = [
  r'HKLM\SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft',
  r'HKLM\SOFTWARE\Blizzard Entertainment\World of Warcraft',
];

// Common install folders, Battle.net's default first. Unverified: community
// sources.
const List<String> _windowsFolders = [
  r'Program Files (x86)\World of Warcraft',
  r'Program Files\World of Warcraft',
  r'Games\World of Warcraft',
];

final RegExp _installPathLine = RegExp(
  r'^\s*InstallPath\s+REG_(?:EXPAND_)?SZ\s+(.+?)\s*$',
  multiLine: true,
);

// A `%name%` in a REG_EXPAND_SZ value.
final RegExp _variable = RegExp('%([^%]+)%');

/// A folder name of one game version, such as `_retail_`.
final RegExp flavorName = RegExp(r'^_.+_$');

/// The folders that may be a WoW install folder on the system of [env], most
/// likely first. A path may appear twice, and most of them do not exist.
Future<List<String>> installCandidates(Environment env) async {
  switch (env.operatingSystem) {
    case 'windows':
      return [...await _registryCandidates(env), ..._windowsCandidates(env)];
    case 'macos':
      return _macCandidates(env);
    case 'linux':
      return _linuxCandidates(env);
    default:
      return [];
  }
}

Future<List<String>> _registryCandidates(Environment env) async {
  final ctx = env.pathContext;
  final out = <String>[];
  // A full path: Windows looks for a bare `reg` in the current folder first,
  // where any reg.exe would run.
  // `\x` is absolute for `package:path` but names a folder on the current
  // drive; a full path starts with a drive or a share.
  bool full(String path) => ctx.rootPrefix(path).length > 1;
  final root = env.env['SystemRoot'];
  final reg = ctx.join(
    root != null && full(root) ? root : r'C:\Windows',
    'System32',
    'reg.exe',
  );
  final results = await Future.wait([
    for (final key in _registryKeys)
      env.runProcess(reg, ['query', key, '/v', 'InstallPath']),
  ]);
  for (final r in results) {
    if (r == null || r.exitCode != 0) continue;
    final match = _installPathLine.firstMatch(r.stdout);
    if (match == null) continue;
    final value = ctx.normalize(
      match
          .group(1)!
          .replaceAllMapped(
            _variable,
            (m) => env.env[m.group(1)!] ?? m.group(0)!,
          ),
    );
    // A value that is not a full path, such as one with an unknown variable,
    // would name a folder that depends on the current folder of the app.
    if (!full(value)) continue;
    // The value names a flavor folder, but an old client or a hand edit can
    // name the install folder or a drive root; that one is the install folder.
    out.add(
      flavorName.hasMatch(ctx.basename(value)) ? ctx.dirname(value) : value,
    );
  }
  return out;
}

List<String> _windowsCandidates(Environment env) {
  final drives = [
    r'C:\',
    // A: and B: are floppy letters; a look at them can stall or prompt.
    for (var c = 'D'.codeUnitAt(0); c <= 'Z'.codeUnitAt(0); c++)
      if (env.exists('${String.fromCharCode(c)}:\\'))
        '${String.fromCharCode(c)}:\\',
  ];
  return [
    for (final d in drives)
      for (final f in _windowsFolders) env.pathContext.join(d, f),
  ];
}

List<String> _macCandidates(Environment env) => [
  // Blizzard default. Unverified: community sources.
  '/Applications/World of Warcraft',
  // Unverified: community sources.
  if (env.home != null)
    p.posix.join(env.home!, 'Applications', 'World of Warcraft'),
];

// Every Linux path is a Wine, Proton, Bottles or Lutris prefix. Each one is
// unverified: community sources only.
const List<String> _linuxPatterns = [
  'Games/world-of-warcraft',
  'Games/battlenet/drive_c/Program Files (x86)/World of Warcraft',
  // Lutris, native and Flatpak, makes one prefix per game in ~/Games.
  'Games/*/drive_c/Program Files (x86)/World of Warcraft',
  '.wine/drive_c/Program Files (x86)/World of Warcraft',
  '.local/share/Steam/steamapps/compatdata/*/pfx/drive_c/Program Files (x86)/World of Warcraft',
  '.var/app/com.valvesoftware.Steam/.local/share/Steam/steamapps/compatdata/*/pfx/drive_c/Program Files (x86)/World of Warcraft',
  '.var/app/com.usebottles.bottles/data/bottles/bottles/*/drive_c/Program Files (x86)/World of Warcraft',
  '.local/share/bottles/bottles/*/drive_c/Program Files (x86)/World of Warcraft',
];

List<String> _linuxCandidates(Environment env) {
  final home = env.home;
  if (home == null) return [];
  return [
    for (final pattern in _linuxPatterns)
      ..._expand(env, [home], pattern.split('/')),
  ];
}

/// The paths below [bases] that match [segments], where `*` matches the name
/// of any folder.
List<String> _expand(
  Environment env,
  List<String> bases,
  List<String> segments,
) {
  var current = bases;
  for (final s in segments) {
    if (s != '*') {
      current = [for (final b in current) p.posix.join(b, s)];
      continue;
    }
    current = [
      for (final b in current)
        if (env.isDirectory(b)) ..._listOrNone(env, b),
    ];
  }
  return current;
}

List<String> _listOrNone(Environment env, String dir) {
  try {
    return env.listDirectories(dir)..sort();
  } on FileSystemException {
    return [];
  }
}
