import 'dart:io';

import 'package:memories_core/memories_core.dart';

/// Prints the WoW flavor folders found on this system or, given a folder,
/// whether a gather can read it. Exit 0 when a folder is usable, 1 when not,
/// 2 for a usage error.
Future<void> main(List<String> args) async {
  if (args.length > 1 || args.any((a) => a.startsWith('-'))) {
    stderr.writeln('usage: discover [folder]');
    exitCode = 2;
    return;
  }
  if (args.isNotEmpty) {
    final check = validateFlavorDir(args.single);
    stdout.writeln(check.message);
    switch (check) {
      case Valid(:final folder):
        stdout.writeln(_line(folder));
      case IsInstallFolder(:final flavors):
        flavors.map(_line).forEach(stdout.writeln);
      default:
        break;
    }
    exitCode = check is Valid ? 0 : 1;
    return;
  }
  final found = await discoverWow();
  if (found.isEmpty) {
    stdout.writeln('No WoW folder found. Pick it by hand.');
    exitCode = 1;
    return;
  }
  found.map(_line).forEach(stdout.writeln);
}

String _line(WowFolder f) =>
    '${f.flavorDir} (flavor ${f.flavor}, Memories data: '
    '${f.hasMemoriesData ? 'yes' : 'no'})';
