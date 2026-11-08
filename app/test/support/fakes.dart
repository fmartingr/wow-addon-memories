import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:memories_core/memories_core.dart';
import 'package:wow_journey/src/app.dart';
import 'package:wow_journey/src/gather/gather_controller.dart';
import 'package:wow_journey/src/platform/discovery.dart';
import 'package:wow_journey/src/platform/documents_dir.dart';
import 'package:wow_journey/src/platform/folder_opener.dart';
import 'package:wow_journey/src/platform/folder_picker.dart';
import 'package:wow_journey/src/platform/services.dart';
import 'package:wow_journey/src/settings/settings.dart';
import 'package:wow_journey/src/settings/settings_store.dart';

const String install = '/games/World of Warcraft';
const String retailDir = '$install/_retail_';
const String foreverDir = '$install/_forever_';
const String documents = '/home/player/Documents';
const String defaultRoot = '$documents/WoW Journey';

const WowFolder retail = WowFolder(
  installDir: install,
  flavorDir: retailDir,
  flavor: '_retail_',
  hasMemoriesData: true,
);

const WowFolder forever = WowFolder(
  installDir: install,
  flavorDir: foreverDir,
  flavor: '_forever_',
  hasMemoriesData: false,
);

const Settings readySettings = Settings(
  flavorDir: retailDir,
  backupRoot: '/backups/WoW Journey',
  wizardDone: true,
);

class FakeSettingsStore implements SettingsStore {
  FakeSettingsStore([this.loaded = const (settings: Settings(), notice: null)]);

  LoadedSettings loaded;
  final List<Settings> saved = [];
  bool failSave = false;

  @override
  Future<LoadedSettings> load() async => loaded;

  @override
  Future<void> save(Settings settings) async {
    if (failSave) throw const FileSystemExceptionFake();
    saved.add(settings);
    loaded = (settings: settings, notice: null);
  }
}

class FileSystemExceptionFake implements Exception {
  const FileSystemExceptionFake();
}

class FakeDiscovery implements Discovery {
  FakeDiscovery({this.found = const [], Map<String, FlavorCheck>? checks})
    : checks = checks ?? {};

  List<WowFolder> found;
  final Map<String, FlavorCheck> checks;
  int discoverCalls = 0;
  final List<String> validated = [];

  @override
  Future<List<WowFolder>> discover() async {
    discoverCalls++;
    return found;
  }

  @override
  Future<FlavorCheck> validate(String path) async {
    validated.add(path);
    return checks[path] ?? NoWtf(path);
  }
}

/// Answers each pick with the next value of [answers]; null is a cancel.
class FakeFolderPicker implements FolderPicker {
  FakeFolderPicker([List<String?>? answers]) : answers = answers ?? [];

  final List<String?> answers;
  int calls = 0;

  @override
  Future<String?> pickFolder({
    String? initialDirectory,
    String? confirmText,
  }) async {
    calls++;
    return answers.isEmpty ? null : answers.removeAt(0);
  }
}

class FakeDirectories implements AppDirectories {
  const FakeDirectories();

  @override
  Future<String> documents() async => '/home/player/Documents';

  @override
  Future<String> support() async => '/home/player/.support';
}

/// A gather that ends when the test completes [pending], or at once with
/// [next].
class FakeGatherService implements GatherService {
  FakeGatherService({this.snapshot = const BackupSnapshot()});

  BackupSnapshot snapshot;
  GatherReport? next;
  Completer<GatherReport>? pending;
  Object? error;
  final List<(String, String)> calls = [];
  final List<String> inspected = [];

  @override
  Future<GatherReport> gather(String flavorDir, String backupRoot) {
    calls.add((flavorDir, backupRoot));
    if (error != null) return Future.error(error!);
    if (pending != null) return pending!.future;
    return Future.value(
      next ?? (result: const GatherResult(), snapshot: snapshot),
    );
  }

  @override
  Future<BackupSnapshot> inspect(String backupRoot) async {
    inspected.add(backupRoot);
    return snapshot;
  }
}

class FakeOpener implements FolderOpener {
  bool result = true;
  final List<String> opened = [];

  @override
  Future<bool> open(String path) async {
    opened.add(path);
    return result;
  }
}

/// The signature that Watch reads: [value] for every folder, or [error].
/// A call while [held] has a completer waits on the first one.
class FakeSignature {
  FakeSignature([this.value]);

  String? value;
  Object? error;
  final List<String> calls = [];
  final List<Completer<String?>> held = [];

  Future<String?> call(String flavorDir) async {
    calls.add(flavorDir);
    if (held.isNotEmpty) return held.removeAt(0).future;
    if (error != null) throw error!;
    return value;
  }
}

class Fakes {
  Fakes({
    FakeSettingsStore? store,
    FakeDiscovery? discovery,
    FakeFolderPicker? picker,
    FakeGatherService? gather,
    FakeSignature? signature,
  }) : signature = signature ?? FakeSignature(),
       store = store ?? FakeSettingsStore(),
       discovery = discovery ?? FakeDiscovery(),
       picker = picker ?? FakeFolderPicker(),
       gather = gather ?? FakeGatherService();

  final FakeSettingsStore store;
  final FakeDiscovery discovery;
  final FakeFolderPicker picker;
  final FakeGatherService gather;
  final FakeSignature signature;
  final FakeOpener opener = FakeOpener();

  /// The time of Watch; a widget test sets it to the fake time of the test.
  DateTime Function() clock = DateTime.now;

  AppServices get services => AppServices(
    store: store,
    discovery: discovery,
    picker: picker,
    directories: const FakeDirectories(),
    gather: gather,
    opener: opener,
    signature: signature.call,
    clock: () => clock(),
  );
}

/// Pumps the whole app with [fakes] and lets the loads end.
Future<void> pumpApp(WidgetTester tester, Fakes fakes) async {
  await tester.pumpWidget(WowJourneyApp(services: fakes.services));
  await tester.pumpAndSettle();
}

/// A window of [width] by [height] logical pixels with the text scale
/// [textScale].
void useWindow(
  WidgetTester tester, {
  double width = 800,
  double height = 900,
  double textScale = 1,
}) {
  tester.view.physicalSize = Size(width, height);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// Taps the widget that [finder] finds after scrolling it into view.
Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
}

/// The issue [code] as a gather gives it.
GatherIssue issue(GatherIssueCode code, {String? path, bool fatal = false}) =>
    GatherIssue(code, 'core text for $code', path: path, fatal: fatal);
