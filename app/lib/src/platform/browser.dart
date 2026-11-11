/// Opens a web address in the default browser.
library;

import 'package:url_launcher/url_launcher.dart';

/// Shows a web address to the user.
abstract interface class Browser {
  /// Opens [url]. Returns false when no browser could be started.
  Future<bool> open(Uri url);
}

/// Starts the default browser of the system through `url_launcher`.
class SystemBrowser implements Browser {
  const SystemBrowser();

  @override
  Future<bool> open(Uri url) async {
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } on Object {
      return false;
    }
  }
}
