/// The problems and the log lines of a gather.
library;

/// The kind of a problem that a gather met.
enum GatherIssueCode {
  /// The WoW folder has no WTF/Account folder.
  noWtf,

  /// No character has Memories data.
  noData,

  /// A saved file cannot be read or parsed; it is skipped.
  damagedFile,

  /// The account file is missing or damaged, so its characters are skipped.
  accountSkipped,

  /// A character's earlier output cannot be merged; its folder is kept.
  characterFailed,

  /// An output folder is inside WTF or Screenshots, or holds one of them.
  overlap,

  /// Another gather runs on the same backup root.
  lockHeld,

  /// An output folder cannot be written.
  notWritable,

  /// The earlier index.json cannot be read.
  badIndex,

  /// The default character id names no character. It stops the gather, or,
  /// when the character has no entry in index.json, falls back to another.
  badDefault,

  /// A saved file has no Memories table, or belongs to another character; it
  /// is skipped.
  skippedFile,

  /// Two character folders hold one GUID; the one played last is kept.
  duplicateGuid,

  /// A copy into the backup folder failed.
  backupFailed,

  /// A matched screenshot cannot be copied.
  screenshotFailed,

  /// A file operation failed and stopped the gather.
  ioError;

  /// Whether the options of the gather are wrong, as opposed to its run.
  bool get isUsage => this == overlap || this == badDefault;
}

/// One problem of a gather. A [fatal] problem stopped the gather.
class GatherIssue {
  const GatherIssue(this.code, this.message, {this.path, this.fatal = false});

  final GatherIssueCode code;
  final String message;
  final String? path;
  final bool fatal;

  @override
  String toString() => message;
}

/// One log line of a gather.
class GatherEvent {
  const GatherEvent(this.message, {this.warning = false});

  final String message;
  final bool warning;

  /// The line as the command line tool prints it.
  String get line => warning ? 'warning: $message' : message;

  @override
  String toString() => line;
}
