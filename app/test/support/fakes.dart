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
import 'package:wow_journey/src/platform/single_instance.dart';
import 'package:wow_journey/src/platform/startup_service.dart';
import 'package:wow_journey/src/platform/tray_service.dart';
import 'package:wow_journey/src/platform/window_service.dart';
import 'package:wow_journey/src/settings/settings.dart';
import 'package:wow_journey/src/settings/settings_store.dart';
import 'package:wow_journey/src/upload/upload_service.dart';

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

/// A tray that shows when [shows] is true and keeps the menu it was given.
class FakeTray implements TrayService {
  FakeTray({this.shows = true});

  bool shows;
  List<TrayItem> items = [];
  String tooltip = '';
  bool disposed = false;
  bool _available = false;

  @override
  bool get available => _available;

  @override
  Future<bool> start(List<TrayItem> items, {required String tooltip}) async {
    this.items = items;
    this.tooltip = tooltip;
    return _available = shows;
  }

  @override
  Future<void> update(List<TrayItem> items, {required String tooltip}) async {
    this.items = items;
    this.tooltip = tooltip;
    updates++;
  }

  /// How many times the menu was replaced.
  int updates = 0;

  @override
  Future<void> dispose() async {
    disposed = true;
    _available = false;
  }

  /// Selects the menu item [label], as a click on it does.
  void select(String label) =>
      items.singleWhere((i) => i.label == label).onSelected();
}

/// Records the calls of the app on its window.
class FakeWindow implements WindowService {
  final List<String> calls = [];
  Future<void> Function()? onCloseRequested;

  @override
  Future<void> init({required Future<void> Function() onCloseRequested}) async {
    calls.add('init');
    this.onCloseRequested = onCloseRequested;
  }

  @override
  Future<void> show() async => calls.add('show');

  @override
  Future<void> hide() async => calls.add('hide');

  @override
  Future<void> quit() async => calls.add('quit');

  /// Clicks the close button of the window.
  Future<void> close() => onCloseRequested!();
}

class FakeStartup implements StartupService {
  final List<bool> applied = [];

  @override
  Future<bool> apply(bool enabled) async {
    applied.add(enabled);
    return true;
  }
}

/// Answers each claim with [claim], or throws [error].
class FakeSingleInstance implements SingleInstance {
  FakeSingleInstance(this.claimResult);

  InstanceClaim claimResult;
  Object? error;

  @override
  Future<InstanceClaim> claim() async {
    if (error != null) throw error!;
    return claimResult;
  }
}

class FakeFirstInstance extends FirstInstance {
  final StreamController<void> requests = StreamController.broadcast();
  bool released = false;

  @override
  Stream<void> get showRequests => requests.stream;

  @override
  Future<void> release() async => released = true;
}

/// A website that answers from fields the test sets, and records each call.
/// A field holding an error makes that method throw it.
class FakeUploadService implements UploadService {
  /// The sites where the key is registered.
  final Set<String> registeredSites = {};
  String? fingerprint;
  SiteInfo siteInfo = const SiteInfo(
    api: 1,
    name: 'Journey Site',
    registration: 'invite',
  );
  MeInfo meInfo = const MeInfo(screenshots: 'none', characters: []);
  SyncReport? report;

  Object? statusError;
  Object? infoError;
  Object? registerError;
  Object? meError;
  Object? syncError;
  Object? deleteError;
  Object? requestError;
  Object? replaceError;

  /// The fingerprint of the key that [replaceKey] makes.
  String newFingerprint = 'fedcba9876543210';

  /// A new key that is made when the test completes it.
  Completer<void>? pendingReplace;

  /// A sync that ends when the test completes it.
  Completer<SyncReport>? pendingSync;

  /// The progress callback of the running sync, for a test to call.
  void Function(int done, int total)? onProgress;

  /// The state that [requestScreenshots] gives back.
  String requested = 'pending';

  final List<String> calls = [];
  final List<(String, String)> syncs = [];

  /// The selection of each sync.
  final List<Set<String>> syncSelections = [];

  /// The character paths chosen for each site, as the state file keeps them.
  final Map<String, Set<String>> selections = {};

  /// Every selection that [setSelected] saved, in order.
  final List<Set<String>> savedSelections = [];

  /// A save of the selection that fails with this error.
  Object? selectError;
  final List<(String, String?)> registrations = [];
  final List<(String, String)> deletions = [];

  @override
  Future<SiteStatus> status(String site) async {
    if (statusError != null) throw statusError!;
    return (
      registered: registeredSites.contains(site),
      fingerprint: fingerprint,
      selected: {...?selections[site]},
    );
  }

  @override
  Future<SiteInfo> info(String site) async {
    calls.add('info $site');
    if (infoError != null) throw infoError!;
    return siteInfo;
  }

  @override
  Future<void> register(String site, String? invite) async {
    calls.add('register $site');
    registrations.add((site, invite));
    if (registerError != null) throw registerError!;
    registeredSites.add(site);
    fingerprint ??= '0123456789abcdef';
  }

  @override
  Future<MeInfo> me(String site) async {
    calls.add('me $site');
    if (meError != null) throw meError!;
    return meInfo;
  }

  @override
  Future<SyncReport> sync(
    String site,
    String latestDir,
    Set<String> selected, {
    void Function(int done, int total)? onProgress,
  }) {
    this.onProgress = onProgress;
    calls.add('sync $site');
    syncs.add((site, latestDir));
    syncSelections.add({...selected});
    if (syncError != null) return Future.error(syncError!);
    if (pendingSync != null) return pendingSync!.future;
    return Future.value(
      report ?? SyncReport(screenshots: meInfo.screenshots, characters: []),
    );
  }

  @override
  Future<void> setSelected(String site, Set<String> selected) async {
    calls.add('setSelected $site');
    if (selectError != null) throw selectError!;
    selections[site] = {...selected};
    savedSelections.add({...selected});
  }

  @override
  Future<void> delete(String site, String path) async {
    calls.add('delete $site $path');
    deletions.add((site, path));
    if (deleteError != null) throw deleteError!;
    selections[site]?.remove(path);
    meInfo = MeInfo(
      screenshots: meInfo.screenshots,
      characters: [
        for (final c in meInfo.characters)
          if (c.path != path) c,
      ],
    );
  }

  @override
  Future<String> requestScreenshots(String site) async {
    calls.add('requestScreenshots $site');
    if (requestError != null) throw requestError!;
    meInfo = MeInfo(screenshots: requested, characters: meInfo.characters);
    return requested;
  }

  @override
  Future<String> replaceKey() async {
    calls.add('replaceKey');
    if (replaceError != null) throw replaceError!;
    if (pendingReplace != null) await pendingReplace!.future;
    registeredSites.clear();
    fingerprint = newFingerprint;
    meInfo = const MeInfo(screenshots: 'none', characters: []);
    return newFingerprint;
  }
}

class Fakes {
  Fakes({
    FakeSettingsStore? store,
    FakeDiscovery? discovery,
    FakeFolderPicker? picker,
    FakeGatherService? gather,
    FakeSignature? signature,
    FakeUploadService? upload,
  }) : upload = upload ?? FakeUploadService(),
       signature = signature ?? FakeSignature(),
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
  final FakeTray tray = FakeTray();
  final FakeWindow window = FakeWindow();
  final FakeStartup startup = FakeStartup();
  final FakeUploadService upload;

  /// The texts put on the clipboard.
  final List<String> copied = [];

  /// The time of Watch; a widget test sets it to the fake time of the test.
  DateTime Function() clock = DateTime.now;

  AppServices get services => AppServices(
    store: store,
    discovery: discovery,
    picker: picker,
    directories: const FakeDirectories(),
    gather: gather,
    opener: opener,
    tray: tray,
    window: window,
    startup: startup,
    uploader: upload,
    signature: signature.call,
    clock: () => clock(),
    copyText: (text) async => copied.add(text),
  );
}

/// Pumps the whole app with [fakes] and lets the loads end.
Future<void> pumpApp(
  WidgetTester tester,
  Fakes fakes, {
  bool startHidden = false,
  Stream<void>? showRequests,
}) async {
  await tester.pumpWidget(
    WowJourneyApp(
      services: fakes.services,
      startHidden: startHidden,
      showRequests: showRequests,
    ),
  );
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

/// Opens the tab [label] of the main screen (Overview, Website or Settings).
Future<void> openTab(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(ValueKey('tab-$label')));
  await tester.pumpAndSettle();
}
