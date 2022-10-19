import 'package:uuid/uuid.dart';

extension UriExtenstion on Uri {
  /// Creates an [Uri] valid for an actor path.
  static Uri actor(String path, {String? system}) {
    return Uri(scheme: 'actor', host: system, path: path);
  }

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
