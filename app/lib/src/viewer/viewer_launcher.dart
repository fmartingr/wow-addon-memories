/// Starts the local viewer server at the first View and opens a character
/// page in the default browser.
library;

import 'package:path/path.dart' as p;

import '../platform/browser.dart';
import 'viewer_files.dart';
import 'viewer_server.dart';

/// The result of [ViewerLauncher.open].
sealed class ViewerResult {
  const ViewerResult();
}

/// The browser got the page address.
final class ViewerOpened extends ViewerResult {
  const ViewerOpened();
}

/// The server could not start.
final class ViewerServerFailed extends ViewerResult {
  const ViewerServerFailed();
}

/// The server runs but the browser did not start. The player can open [url].
final class ViewerBrowserFailed extends ViewerResult {
  const ViewerBrowserFailed(this.url);

  final Uri url;
}

class ViewerLauncher {
  ViewerLauncher({required ViewerFiles files, required this._browser}) {
    _server = ViewerServer(files: files, latestDir: _latestDir);
  }

  final Browser _browser;
  late final ViewerServer _server;

  /// The backup folder that the server reads `latest/` from. The app sets it
  /// at each change of the setting.
  String? backupRoot;

  String? _latestDir() {
    final root = backupRoot;
    return root == null ? null : p.join(root, 'latest');
  }

  /// Opens the page of character [id] in language [lang].
  Future<ViewerResult> open(String id, String lang) async {
    try {
      await _server.start();
    } on ViewerServerException {
      return const ViewerServerFailed();
    }
    final url = _server.pageUrl(id, lang);
    return await _browser.open(url)
        ? const ViewerOpened()
        : ViewerBrowserFailed(url);
  }

  /// Stops the server. Call it when the app quits.
  Future<void> close() => _server.close();
}
