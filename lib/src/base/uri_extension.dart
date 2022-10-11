import 'package:uuid/uuid.dart';

extension UriExtenstion on Uri {
  Uri actorPath(Iterable<Uri> existingPaths) {
    if (pathSegments.last.isNotEmpty) {
      return this;
    } else {
      var result = this.resolve(Uuid().v4());
      while (existingPaths.contains(result)) {
        result = this.resolve(Uuid().v4());
      }
      return result;
    }
  }
}
