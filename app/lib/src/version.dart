/// The version of the app that the settings page shows. A release build
/// passes `--dart-define=APP_VERSION=<version>`; the default is the version
/// in `pubspec.yaml`.
const String appVersion = String.fromEnvironment(
  'APP_VERSION',
  defaultValue: '0.1.0',
);
