/// The Watch and Start at login switches of the wizard and the settings.
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';

class WatchTile extends StatelessWidget {
  const WatchTile({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SwitchListTile(
      title: Text(l.watchTitle),
      subtitle: Text(l.watchSubtitle),
      value: value,
      onChanged: onChanged,
    );
  }
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
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    return SwitchListTile(
      title: Text(l.startAtLoginTitle),
      subtitle: Text(l.startAtLoginSubtitle),
      value: value,
      onChanged: onChanged,
    );
  }
}
