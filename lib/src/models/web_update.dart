/// Web client: is a newer build served than the one running?
///
/// The CI writes `sarcade_build.json` next to the web app with the build
/// (« branch@commit », same as SARCADE_BUILD). A PWA or an open tab keeps
/// running the old code until it is reloaded: when the served build differs,
/// the map shows « Nouvelle version disponible · Mettre à jour ».
/// Local builds (no SARCADE_BUILD) and unreadable answers never prompt.
bool webUpdateAvailable(String running,String? served){
  final s=served?.trim()??'';
  return running.isNotEmpty&&s.isNotEmpty&&s!=running;
}

/// Version and build number served (« 0.1.0+560 »), written by the CI
/// since the card « Bandeau Nouvelle version avec les numéros », or null.
String? parseServedVersion(Object? json){
  if(json is Map&&json['version'] is String&&(json['version'] as String).trim().isNotEmpty)return (json['version'] as String).trim();
  return null;
}

/// « (0.1.0+535 → 0.1.0+560) », put before « Nouvelle version disponible »
/// on the web, mobile and Windows alike; empty when a number is unknown.
String versionChange(String current,String? target){
  final t=target?.trim()??'';
  if(current.trim().isEmpty||t.isEmpty||t==current)return '';
  return '($current → $t) ';
}

/// Build read from the content of `sarcade_build.json`, or null.
String? parseServedBuild(Object? json){
  if(json is Map&&json['build'] is String)return json['build'] as String;
  return null;
}
