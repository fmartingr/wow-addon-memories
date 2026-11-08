/// The Watch and Start at login switches of the wizard and the settings.
library;

import 'package:flutter/material.dart';

class WatchTile extends StatelessWidget {
  const WatchTile({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    title: const Text('Watch'),
    subtitle: const Text('Gather on its own each time the game saves.'),
    value: value,
    onChanged: onChanged,
  );
}

class StartAtLoginTile extends StatelessWidget {
  const StartAtLoginTile({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SwitchListTile(
    title: const Text('Start at login'),
    subtitle: const Text('Start the app hidden when you sign in.'),
    value: value,
    onChanged: onChanged,
  );
}
