/// The choices of the user, kept in `settings.json`.
library;

/// The website that gets the uploads, unless the user chose another. A build
/// can set it with `--dart-define=WOWJOURNEY_SITE=...`.
const String defaultSite = String.fromEnvironment(
  'WOWJOURNEY_SITE',
  defaultValue: 'https://wowjourney.xyz',
);

/// The settings of the app. A new value replaces the old one as a whole.
class Settings {
  const Settings({
    this.flavorDir,
    this.backupRoot,
    this.watch = true,
    this.startAtLogin = true,
    this.wizardDone = false,
    this.lastSignature,
    this.site = defaultSite,
    this.upload = false,
  });

  /// The flavor folder that a gather reads, such as `.../_retail_`.
  final String? flavorDir;

  /// The folder that holds `latest/` and `backups/`.
  final String? backupRoot;

  /// Whether the app gathers when the game saves its files.
  final bool watch;

  /// Whether the app starts with the system.
  final bool startAtLogin;

  /// Whether the first-run wizard has ended.
  final bool wizardDone;

  /// The signature of the Memories files at the last gather of Watch.
  final String? lastSignature;

  /// The address of the website that gets the uploads.
  final String site;

  /// Whether the app uploads after each gather. It stays off until the key
  /// is registered on [site].
  final bool upload;

  Settings copyWith({
    String? flavorDir,
    String? backupRoot,
    bool? watch,
    bool? startAtLogin,
    bool? wizardDone,
    String? lastSignature,
    bool clearLastSignature = false,
    String? site,
    bool? upload,
  }) => Settings(
    flavorDir: flavorDir ?? this.flavorDir,
    backupRoot: backupRoot ?? this.backupRoot,
    watch: watch ?? this.watch,
    startAtLogin: startAtLogin ?? this.startAtLogin,
    wizardDone: wizardDone ?? this.wizardDone,
    lastSignature: clearLastSignature
        ? null
        : lastSignature ?? this.lastSignature,
    site: site ?? this.site,
    upload: upload ?? this.upload,
  );

  Map<String, Object?> toJson() => {
    'flavorDir': flavorDir,
    'backupRoot': backupRoot,
    'watch': watch,
    'startAtLogin': startAtLogin,
    'wizardDone': wizardDone,
    'lastSignature': lastSignature,
    'site': site,
    'upload': upload,
  };

  /// Reads [json] as [toJson] writes it. A missing key takes its default.
  /// Throws a [FormatException] when a value has the wrong type.
  factory Settings.fromJson(Object? json) {
    if (json is! Map<String, Object?>) {
      throw const FormatException('settings are not an object');
    }
    T? read<T>(String key) {
      final v = json[key];
      if (v == null || v is T) return v as T?;
      throw FormatException('$key has the wrong type');
    }

    const d = Settings();
    return Settings(
      flavorDir: read<String>('flavorDir'),
      backupRoot: read<String>('backupRoot'),
      watch: read<bool>('watch') ?? d.watch,
      startAtLogin: read<bool>('startAtLogin') ?? d.startAtLogin,
      wizardDone: read<bool>('wizardDone') ?? d.wizardDone,
      lastSignature: read<String>('lastSignature'),
      site: read<String>('site') ?? d.site,
      upload: read<bool>('upload') ?? d.upload,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is Settings &&
      other.flavorDir == flavorDir &&
      other.backupRoot == backupRoot &&
      other.watch == watch &&
      other.startAtLogin == startAtLogin &&
      other.wizardDone == wizardDone &&
      other.lastSignature == lastSignature &&
      other.site == site &&
      other.upload == upload;

  @override
  int get hashCode => Object.hash(
    flavorDir,
    backupRoot,
    watch,
    startAtLogin,
    wizardDone,
    lastSignature,
    site,
    upload,
  );

  @override
  String toString() => 'Settings(${toJson()})';
}
