/// The login entry that starts the app hidden with the system.
library;

import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:path/path.dart' as p;

/// The start argument of the login entry: start with the window hidden.
const String hiddenArgument = '--hidden';

/// The name of the login entry, as the system lists it.
const String startupName = 'WoW Journey';

/// The bundle id of the macOS app, also the label of its launch agent.
const String macBundleId = 'com.fmartingr.wowJourney';

/// Adds or removes the login entry.
abstract interface class StartupService {
  /// Registers the app at [Platform.resolvedExecutable] to start with
  /// [hiddenArgument] at login when [enabled], else removes that entry.
  /// Returns false when the system refused it.
  Future<bool> apply(bool enabled);
}

/// [path] as one argument of the `Exec` key of a desktop entry: quoted, with
/// the quoting escapes, then the string escapes of the key value.
@visibleForTesting
String desktopExecArgument(String path) {
  final quoted = path.replaceAllMapped(RegExp(r'["`$\\]'), (m) => '\\${m[0]}');
  return '"${quoted.replaceAll(r'\', r'\\').replaceAll('%', '%%')}"';
}

String _xml(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');

/// The launch agent that starts [executable] hidden at login on macOS.
@visibleForTesting
String launchAgentPlist(String executable) =>
    '''
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$macBundleId</string>
  <key>AssociatedBundleIdentifiers</key>
  <string>$macBundleId</string>
  <key>ProgramArguments</key>
  <array>
    <string>${_xml(executable)}</string>
    <string>$hiddenArgument</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
</dict>
</plist>
''';

/// The login entry of the system: the `Run` registry key on Windows and an
/// autostart desktop file on Linux, through `launch_at_startup`, and a launch
/// agent on macOS.
///
/// On macOS `launch_at_startup` needs the LaunchAtLogin Swift package added in
/// Xcode and starts the app with no arguments, so this class writes the
/// launch agent itself.
class SystemStartupService implements StartupService {
  SystemStartupService({
    String? executable,
    String? operatingSystem,
    String? home,
  }) : executable = executable ?? Platform.resolvedExecutable,
       operatingSystem = operatingSystem ?? Platform.operatingSystem,
       home = home ?? Platform.environment['HOME'];

  final String executable;
  final String operatingSystem;

  /// The home folder of the user; macOS keeps launch agents under it.
  final String? home;

  @override
  Future<bool> apply(bool enabled) async {
    // A line break would end the entry early and could add keys to it.
    if (executable.contains(RegExp(r'[\r\n]'))) return false;
    try {
      if (operatingSystem == 'macos') return await _applyMac(enabled);
      if (operatingSystem != 'linux' && operatingSystem != 'windows') {
        return false;
      }
      launchAtStartup.setup(
        appName: startupName,
        // The package writes the path as it is, so a path with a space would
        // break into two arguments.
        appPath: operatingSystem == 'linux'
            ? desktopExecArgument(executable)
            : '"$executable"',
        args: const [hiddenArgument],
      );
      return enabled
          ? await launchAtStartup.enable()
          : await launchAtStartup.disable();
    } on Object catch (e) {
      debugPrint('launch at login: $e');
      return false;
    }
  }

  Future<bool> _applyMac(bool enabled) async {
    if (home == null) return false;
    final file = File(
      p.join(home!, 'Library', 'LaunchAgents', '$macBundleId.plist'),
    );
    if (!enabled) {
      if (await file.exists()) await file.delete();
      return true;
    }
    await file.parent.create(recursive: true);
    final tmp = File(
      p.join(file.parent.path, '.$macBundleId-${Random().nextInt(1 << 32)}'),
    );
    try {
      await tmp.writeAsString(launchAgentPlist(executable), flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
    return true;
  }
}
