import 'dart:io';

/// Holds an exclusive lock on the file in the first argument until stdin
/// closes, so a test can see a gather meet a lock of another process.
Future<void> main(List<String> args) async {
  final file = File(args.first).openSync(mode: FileMode.append);
  file.lockSync(FileLock.exclusive);
  stdout.writeln('locked');
  await stdout.flush();
  await stdin.drain<void>();
  file.closeSync();
}
