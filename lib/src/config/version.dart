/// Version of the client application, sent to the server (heartbeat and
/// minimal version check). Keep in step with `version:` in pubspec.yaml;
/// release builds override it with --dart-define=SARCADE_APP_VERSION=x.y.z.
const appVersion=String.fromEnvironment('SARCADE_APP_VERSION',defaultValue:'0.1.0');
/// Branch and commit of a test build (« feat/x@1a2b3c4 »), set by the CI:
/// tells test APKs apart, all numbered 0.1.0-dev.
const appBuild=String.fromEnvironment('SARCADE_BUILD');
/// Build number of the CI run (« 415 »), empty for a local build.
const appBuildNumber=String.fromEnvironment('SARCADE_BUILD_NUMBER');
/// « 0.1.0+415 »: version and build, sent to the server and shown in the
/// operator sheet (« Version de l'application et connexions »).
const appVersionFull=appBuildNumber==''?appVersion:'$appVersion+$appBuildNumber';
