/// The system access that the screens use, in one place so that tests pass
/// fakes.
library;

import '../gather/gather_controller.dart';
import '../settings/settings_store.dart';
import '../watch/watch_controller.dart';
import 'discovery.dart';
import 'documents_dir.dart';
import 'folder_opener.dart';
import 'folder_picker.dart';
import 'startup_service.dart';
import 'tray_service.dart';
import 'window_service.dart';

class AppServices {
  const AppServices({
    required this.store,
    required this.discovery,
    required this.picker,
    required this.directories,
    required this.gather,
    required this.opener,
    required this.tray,
    required this.window,
    required this.startup,
    this.signature = flavorSignature,
    this.clock = DateTime.now,
  });

  final SettingsStore store;
  final Discovery discovery;
  final FolderPicker picker;
  final AppDirectories directories;
  final GatherService gather;
  final FolderOpener opener;
  final TrayService tray;
  final WindowService window;
  final StartupService startup;

  /// The signature of the Memories files that Watch polls.
  final SignatureFunction signature;

  /// The time that Watch measures with.
  final DateTime Function() clock;
}
