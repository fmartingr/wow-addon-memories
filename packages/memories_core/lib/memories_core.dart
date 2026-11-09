/// Reads Memories saved files and gathers the journey data.
library;

export 'src/discovery/candidates.dart' show Environment, ProcessOutput;
export 'src/discovery/discovery.dart';
export 'src/gather/gather.dart' show GatherOptions, GatherResult, gather;
export 'src/gather/issues.dart';
export 'src/journal/journal.dart';
export 'src/journal/trail.dart';
export 'src/savedvars/parser.dart'
    show SavedVarsException, maxDepth, maxInputSize, maxTables, parseSavedVars;
export 'src/upload/client.dart';
export 'src/upload/key.dart' show UploadKey, UploadKeyException;
export 'src/upload/signer.dart' show signRequest;
export 'src/upload/site.dart' show SiteError, SiteFormatException, parseSite;
export 'src/upload/state.dart';
export 'src/upload/sync.dart';
export 'src/watch/signature.dart';

/// The version of the gather library.
const String memoriesCoreVersion = '0.1.0';

/// The name and version of the gather library, for the CLI and the app.
String describeCore() => 'memories_core $memoriesCoreVersion';
