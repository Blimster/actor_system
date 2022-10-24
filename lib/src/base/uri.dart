import 'package:uuid/uuid.dart';

/// Placeholder for the local actor system.
const localSystem = 'local';

/// Scheme for an actor path.
const actorScheme = 'actor';

extension UriExtenstion on Uri {
  /// Completes the [Uri] to be a full actor path.
  ///
  /// If this [Uri] is already a full actor path (does not end with a /), it is
  /// returned as is.
  ///
  /// Otherwise, an UUID is appended as the last segment of the path. The given
  /// [existingPaths] are considered to not complete to an existing path.
  Uri completeActorPath(Iterable<String> existingPaths) {
    if (this.pathSegments.last.isNotEmpty) {
      return this;
    } else {
      var result = this.resolve(Uuid().v4());
      while (existingPaths.contains(result.path)) {
        result = this.resolve(Uuid().v4());
      }
      return result;
    }
  }
}

/// Creates an [Uri] valid for an actor path.
Uri actorPath(String path, {String? system}) {
  return Uri(scheme: actorScheme, host: system, path: path);
}

/// Create an [Uri] for an actor path in the local actor system.
Uri localActorPath(String path) {
  return actorPath(path, system: localSystem);
}
