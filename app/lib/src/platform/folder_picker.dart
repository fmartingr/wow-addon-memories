/// The native folder picker.
library;

import 'package:file_selector/file_selector.dart' as fs;

/// Asks the user for a folder.
abstract interface class FolderPicker {
  /// The folder the user chose, or null when they cancelled.
  Future<String?> pickFolder({String? initialDirectory, String? confirmText});
}

/// The picker of the system, through `file_selector`.
class SystemFolderPicker implements FolderPicker {
  const SystemFolderPicker();

  @override
  Future<String?> pickFolder({String? initialDirectory, String? confirmText}) =>
      fs.getDirectoryPath(
        initialDirectory: initialDirectory,
        confirmButtonText: confirmText,
      );
}
