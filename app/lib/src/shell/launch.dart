/// The start of the app: one copy only, and the hidden start.
library;

import 'package:flutter/material.dart';

import '../platform/single_instance.dart';
import '../platform/window_service.dart';
import 'shell_controller.dart';

/// Shown when another copy runs but did not answer.
const String notAnsweringText =
    'WoW Journey is already running, but it did not answer. Quit it from its '
    'tray icon menu, or end it in the task manager, then start it again.';

/// Builds the app of the first copy.
typedef AppBuilder = Widget Function({
  required bool startHidden,
  Stream<void>? showRequests,
});

/// The widget to run for [args], or null when another copy runs and now
/// shows its window, so this one ends.
Future<Widget?> launch({
  required List<String> args,
  required SingleInstance instance,
  required WindowService window,
  required AppBuilder app,
}) async {
  final hidden = startsHidden(args);
  InstanceClaim? claim;
  try {
    claim = await instance.claim();
  } on Object catch (e) {
    // Without the lock, such as on a support folder that cannot be written,
    // the app still runs; only the check for a second copy is lost.
    debugPrint('single instance: $e');
  }
  switch (claim) {
    case OtherInstance(answered: true):
      return null;
    case OtherInstance(answered: false):
      if (hidden) await window.show();
      return AlreadyRunningApp(onClose: window.quit);
    case FirstInstance(:final showRequests):
      return app(startHidden: hidden, showRequests: showRequests);
    case null:
      return app(startHidden: hidden);
  }
}

/// The screen of a copy whose first copy did not answer.
class AlreadyRunningApp extends StatelessWidget {
  const AlreadyRunningApp({super.key, required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'WoW Journey',
    home: Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(notAnsweringText, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(onPressed: onClose, child: const Text('Close')),
            ],
          ),
        ),
      ),
    ),
  );
}
