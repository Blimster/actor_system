/// Placeholder for the local actor system.
const localSystem = 'local';

/// Scheme for an actor path.
const actorScheme = 'actor';

/// Creates an [Uri] valid for an actor path.
Uri actorPath(String path, {String? system}) {
  return Uri(scheme: actorScheme, host: system, path: path);
}

/// Create an [Uri] for an actor path in the local actor system.
Uri localActorPath(String path) {
  return actorPath(path, system: localSystem);
}
