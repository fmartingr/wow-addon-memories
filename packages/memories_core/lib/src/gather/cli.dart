/// The memories-export command line tool.
library;

import 'dart:io';

import 'package:args/args.dart';

import '../cli_flags.dart';
import 'gather.dart';

/// The usage line of the tool.
const String usage =
    'usage: memories-export --wow-dir <flavor dir> [--dist DIR] [--backup DIR] '
    '[--default ID]';

ArgParser _parser() => ArgParser()
  ..addOption(
    'wow-dir',
    help:
        'WoW flavor folder, for example .../World of Warcraft/_forever_ '
        '(required)',
    defaultsTo: '',
  )
  ..addOption('dist', help: 'output folder', defaultsTo: './dist-characters')
  ..addOption(
    'backup',
    help:
        'folder for the timestamped copies of the saved files and screenshots',
    defaultsTo: './backups',
  )
  ..addOption(
    'default',
    help:
        'id of the character the website opens first (default: the earlier '
        'choice, else the one played last)',
    defaultsTo: '',
  )
  ..addFlag('help', abbr: 'h', negatable: false, help: 'show this help');

/// Runs the tool with [args] and returns its exit code: 0 when it passed, 1
/// for an error during the run, 2 for an error in the arguments.
Future<int> runMemoriesExport(
  List<String> args, {
  required StringSink out,
  required StringSink err,
  DateTime Function() now = DateTime.now,
}) async {
  final parser = _parser();
  final ArgResults opts;
  try {
    opts = parser.parse(longFlags(args, _valued));
  } on ArgParserException catch (e) {
    err
      ..writeln(flagError(e))
      ..writeln('Usage of memories-export:')
      ..writeln(parser.usage);
    return 2;
  }
  if (opts.flag('help')) {
    err
      ..writeln('Usage of memories-export:')
      ..writeln(parser.usage);
    return 0;
  }
  final wowDir = opts.option('wow-dir')!;
  final dist = opts.option('dist')!;
  final backup = opts.option('backup')!;
  if (wowDir.isEmpty ||
      dist.isEmpty ||
      backup.isEmpty ||
      opts.rest.isNotEmpty) {
    err.writeln(usage);
    return 2;
  }
  final result = await gather(
    GatherOptions(
      wowDir: Directory(wowDir),
      dist: Directory(dist),
      backup: Directory(backup),
      defaultId: opts.option('default')!,
      now: now(),
      onEvent: (e) => out.writeln(e.line),
    ),
  );
  final error = result.error;
  if (error == null) return 0;
  final usageError = result.stop?.code.isUsage ?? false;
  err.writeln('memories-export: ${usageError ? 'usage: ' : ''}$error');
  return usageError ? 2 : 1;
}

const Set<String> _valued = {'wow-dir', 'dist', 'backup', 'default'};
