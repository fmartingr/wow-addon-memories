/// The localization delegates of the app.
library;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:material_ui/material_ui.dart';

import '../../l10n/app_localizations.dart';

/// The delegates of the app texts and of the `material_ui` and `cupertino_ui`
/// texts. The generated `AppLocalizations.localizationsDelegates` names the
/// deprecated delegates of `flutter_localizations`.
const List<LocalizationsDelegate<dynamic>> appLocalizationsDelegates =
    <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ];
