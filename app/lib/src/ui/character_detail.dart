/// The realm, the level and the class of a character, as the Overview and the
/// Website card show them.
library;

import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../gather/gather_controller.dart';
import '../theme/tokens.dart';
import 'messages.dart';

/// The realm, the level and the class of [c]. The class has its game colour.
Widget characterDetail(CharacterSummary c, AppLocalizations l) {
  final cls = c.className;
  final parts = [
    c.realm,
    if (c.level != null) l.characterLevel(c.level!),
  ].where((e) => e.isNotEmpty).toList();
  final hasClass = cls != null && cls.isNotEmpty;
  return Text.rich(
    TextSpan(
      children: [
        TextSpan(text: parts.join(' · ')),
        if (hasClass) ...[
          if (parts.isNotEmpty) const TextSpan(text: ' · '),
          TextSpan(
            text: className(l, cls),
            style: TextStyle(
              color: classColours[cls.toUpperCase()] ?? Tokens.text,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    ),
  );
}
