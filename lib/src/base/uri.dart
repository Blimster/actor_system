import 'package:uuid/uuid.dart';

extension UriExtenstion on Uri {
  static Uri actor(String path, {String? system}) {
    return Uri(scheme: 'actor', host: system, path: path);
  }
}

Uri completeActorPath(Uri path, Iterable<String> existingPaths) {
  if (path.pathSegments.last.isNotEmpty) {
    return path;
  } else {
    var result = path.resolve(Uuid().v4());
    while (existingPaths.contains(result.path)) {
      result = path.resolve(Uuid().v4());
    }
    return result;
  }
}
