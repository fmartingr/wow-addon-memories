/// The flag handling that the command line tools share.
library;

import 'package:args/args.dart';

/// Turns the single-dash form `-name` of each flag into `--name`, so both
/// forms work. A value of a flag in [valued] is left as it is, even when it
/// starts with "-".
List<String> longFlags(List<String> args, Set<String> valued) {
  final out = <String>[];
  var value = false;
  for (final a in args) {
    if (value) {
      out.add(a);
      value = false;
      continue;
    }
    final name = a.replaceFirst(RegExp('^-+'), '').split('=').first;
    final takesValue = valued.contains(name) && !a.contains('=');
    if (a.startsWith('--')) {
      value = takesValue;
    } else if (a.length > 2 && a.startsWith('-')) {
      out.add('-$a');
      value = takesValue;
      continue;
    }
    out.add(a);
  }
  return out;
}

/// The fixed error text of a flag mistake, which scripts read.
String flagError(ArgParserException e) {
  final name = (e.argumentName ?? '').replaceFirst(RegExp('^-+'), '');
  if (e.message.startsWith('Could not find')) {
    return 'flag provided but not defined: -$name';
  }
  if (e.message.startsWith('Missing argument')) {
    return 'flag needs an argument: -$name';
  }
  return e.message;
}
