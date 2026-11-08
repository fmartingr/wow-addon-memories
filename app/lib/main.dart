import 'dart:io';

import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/gather/gather_controller.dart';
import 'src/platform/discovery.dart';
import 'src/platform/documents_dir.dart';
import 'src/platform/folder_opener.dart';
import 'src/platform/folder_picker.dart';
import 'src/platform/services.dart';
import 'src/platform/single_instance.dart';
import 'src/platform/startup_service.dart';
import 'src/platform/tray_service.dart';
import 'src/platform/window_service.dart';
import 'src/settings/settings_store.dart';
import 'src/shell/launch.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  const directories = SystemAppDirectories();
  final window = SystemWindowService();
  final services = AppServices(
    store: FileSettingsStore(directories.support),
    discovery: const SystemDiscovery(),
    picker: const SystemFolderPicker(),
    directories: directories,
    gather: const IsolateGatherService(),
    opener: const SystemFolderOpener(),
    tray: SystemTrayService(),
    window: window,
    startup: SystemStartupService(),
  );
  final app = await launch(
    args: args,
    instance: FileSingleInstance(directories.support),
    window: window,
    app: ({required startHidden, showRequests}) => WowJourneyApp(
      services: services,
      startHidden: startHidden,
      showRequests: showRequests,
    ),
  );
  if (app == null) exit(0);
  runApp(app);
}
