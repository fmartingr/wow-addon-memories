import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/gather/gather_controller.dart';
import 'src/platform/discovery.dart';
import 'src/platform/documents_dir.dart';
import 'src/platform/folder_opener.dart';
import 'src/platform/folder_picker.dart';
import 'src/platform/services.dart';
import 'src/settings/settings_store.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  const directories = SystemAppDirectories();
  runApp(
    WowJourneyApp(
      services: AppServices(
        store: FileSettingsStore(directories.support),
        discovery: const SystemDiscovery(),
        picker: const SystemFolderPicker(),
        directories: directories,
        gather: const IsolateGatherService(),
        opener: const SystemFolderOpener(),
      ),
    ),
  );
}
