/// Finds and checks the WoW folder off the UI isolate.
library;

import 'dart:isolate';

import 'package:memories_core/memories_core.dart';

/// Finds the WoW flavor folders and checks a folder that the user picked.
abstract interface class Discovery {
  /// The flavor folders found on this system, best first.
  Future<List<WowFolder>> discover();

  /// Whether [path] can be gathered.
  Future<FlavorCheck> validate(String path);
}

/// The discovery of `memories_core`. Both calls read the disk synchronously,
/// so each runs in its own isolate.
class SystemDiscovery implements Discovery {
  const SystemDiscovery();

  @override
  Future<List<WowFolder>> discover() => Isolate.run(discoverWow);

  @override
  Future<FlavorCheck> validate(String path) =>
      Isolate.run(() => validateFlavorDir(path));
}
