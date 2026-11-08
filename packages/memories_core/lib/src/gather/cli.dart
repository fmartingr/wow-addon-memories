/// The memories-export command line tool.
library;

import 'dart:io';

import 'package:args/args.dart';

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
    opts = parser.parse(_longFlags(args));
  } on ArgParserException catch (e) {
    err
      ..writeln(_flagError(e))
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

/// Turns the single-dash form `-wow-dir` of each flag into `--wow-dir`, so
/// both forms work. A flag value is left as it is, even when it starts with
/// "-".
List<String> _longFlags(List<String> args) {
  final out = <String>[];
  var value = false;
  for (final a in args) {
    if (value) {
      out.add(a);
      value = false;
      continue;
    }
    final name = _flagName(a);
    final valued = _valued.contains(name) && !a.contains('=');
    if (a.startsWith('--')) {
      value = valued;
    } else if (a.length > 2 && a.startsWith('-')) {
      out.add('-$a');
      value = valued;
      continue;
    }
    out.add(a);
  }
  return out;
}

String _flagName(String arg) =>
    arg.replaceFirst(RegExp('^-+'), '').split('=').first;

/// The fixed error text of a flag mistake, which scripts read.
String _flagError(ArgParserException e) {
  final name = (e.argumentName ?? '').replaceFirst(RegExp('^-+'), '');
  if (e.message.startsWith('Could not find')) {
    return 'flag provided but not defined: -$name';
  }
  if (e.message.startsWith('Missing argument')) {
    return 'flag needs an argument: -$name';
  }
  return e.message;
}
