/// The folders of the system that the app uses.
library;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart' as pp;

/// The name of the default backup folder in the Documents folder.
const String defaultBackupName = 'WoW Journey';

/// The Documents folder and the support folder of the app.
abstract interface class AppDirectories {
  /// The Documents folder of the user.
  Future<String> documents();

  /// The folder where the app keeps its own files, such as the settings.
  Future<String> support();
}

/// The folders of the system, through `path_provider`.
class SystemAppDirectories implements AppDirectories {
  const SystemAppDirectories();

  @override
  Future<String> documents() async =>
      (await pp.getApplicationDocumentsDirectory()).path;

  @override
  Future<String> support() async =>
      (await pp.getApplicationSupportDirectory()).path;
}

/// `<Documents>/WoW Journey`. It is only a path; the first gather creates it.
Future<String> defaultBackupRoot(AppDirectories dirs) async =>
    p.join(await dirs.documents(), defaultBackupName);
