import 'dart:io';

import 'package:memories_core/src/gather/cli.dart';

Future<void> main(List<String> args) async {
  exitCode = await runMemoriesExport(args, out: stdout, err: stderr);
}
