/// Version of the client application, sent to the server (heartbeat and
/// minimal version check). Keep in step with `version:` in pubspec.yaml;
/// release builds override it with --dart-define=SARCADE_APP_VERSION=x.y.z.
const appVersion=String.fromEnvironment('SARCADE_APP_VERSION',defaultValue:'0.1.0');
/// Branch and commit of a test build (« feat/x@1a2b3c4 »), set by the CI:
/// tells test APKs apart, all numbered 0.1.0-dev.
const appBuild=String.fromEnvironment('SARCADE_BUILD');
