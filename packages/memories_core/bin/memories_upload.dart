import 'dart:io';

import 'package:memories_core/src/upload/cli.dart';

Future<void> main(List<String> args) async {
  exitCode = await runMemoriesUpload(args, out: stdout, err: stderr);
}
