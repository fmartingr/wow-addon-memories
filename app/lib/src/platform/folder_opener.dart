/// Opens a folder in the file manager of the system.
library;

import 'dart:io';

/// Shows a folder to the user.
abstract interface class FolderOpener {
  /// Opens [path]. Returns false when the folder does not exist or the file
  /// manager could not start.
  Future<bool> open(String path);
}

/// Starts the file manager of the system: Explorer, Finder or `xdg-open`.
class SystemFolderOpener implements FolderOpener {
  const SystemFolderOpener();

  @override
  Future<bool> open(String path) async {
    if (!await Directory(path).exists()) return false;
    final (exe, args) = Platform.isWindows
        ? ('explorer.exe', [path])
        : Platform.isMacOS
        ? ('open', [path])
        : ('xdg-open', [path]);
    try {
      // Explorer returns 1 even when it opened the folder, so only a failed
      // start counts as an error.
      await Process.start(exe, args, mode: ProcessStartMode.detached);
      return true;
    } on ProcessException {
      return false;
    }
  }
}
