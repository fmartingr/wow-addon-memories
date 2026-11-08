/// Reads Memories saved files and gathers the journey data.
library;

export 'src/savedvars/parser.dart'
    show SavedVarsException, maxDepth, maxInputSize, maxTables, parseSavedVars;

/// The version of the gather library.
const String memoriesCoreVersion = '0.1.0';

/// The name and version of the gather library, for the CLI and the app.
String describeCore() => 'memories_core $memoriesCoreVersion';
