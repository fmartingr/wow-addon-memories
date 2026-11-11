/// Where the local viewer server reads the viewer files (the copy of `web/`).
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reads a viewer file by its path relative to the viewer root, with `/`.
abstract interface class ViewerFiles {
  /// The bytes of the file, or null when the file does not exist.
  Future<Uint8List?> read(String path);
}

/// The viewer files in the asset bundle (`assets/viewer/`).
class BundleViewerFiles implements ViewerFiles {
  const BundleViewerFiles();

  @override
  Future<Uint8List?> read(String path) async {
    try {
      final data = await rootBundle.load('assets/viewer/$path');
      return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    } on FlutterError {
      return null;
    }
  }
}

/// The viewer files in a folder. Tests use it with `../web`.
class DirectoryViewerFiles implements ViewerFiles {
  const DirectoryViewerFiles(this.root);

  final Directory root;

  @override
  Future<Uint8List?> read(String path) async {
    if (path.split('/').any((s) => s.isEmpty || s.startsWith('.'))) {
      return null;
    }
    final file = File('${root.path}/$path');
    try {
      return await file.readAsBytes();
    } on FileSystemException {
      return null;
    }
  }
}
