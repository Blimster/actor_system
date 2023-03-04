import 'package:logging/logging.dart';

/// A nullable reference to a value. The reference itself can be shared.
class NullableRef<T> {
  T? value;
}

extension StringExtension on String {
  /// Abbreviate the string to the given [length].
  String abbreviate(int maxLength) {
    if (length > maxLength) {
      return '...${substring(length - maxLength + 3)}';
    }
    return this;
  }

  /// Returns a [Level] from this string. See [Level.LEVELS] for valid strings.
  Level toLogLevel() {
    return Level.LEVELS.firstWhere((element) => element.name == toUpperCase());
  }
}

/// Placeholder for the local actor system.
const localSystem = 'local';

/// Scheme for an actor path.
const actorScheme = 'actor';

/// Creates an [Uri] valid for an actor path.
Uri actorPath(String path, {String? system, String? tag}) {
  return Uri(scheme: actorScheme, host: system, path: path, fragment: tag);
}

/// Creates an [Uri] for an actor path in the local actor system.
Uri localActorPath(String path) {
  return actorPath(path, system: localSystem);
}

extension UriExtension on Uri {
  /// Ensures that the right scheme is set and only applies
  /// relevant parts of the Uri.
  Uri validActorPath() => Uri(
        scheme: actorScheme,
        host: host,
        path: path,
        fragment: fragment.isEmpty ? null : fragment,
      );

  /// Creates a copy of this path with the possibility to
  /// adapt the system, path and fragment.
  Uri copyWith({String? system, String? path, String? tag}) {
    return Uri(
      scheme: actorScheme,
      host: system ?? host,
      path: path ?? this.path,
      fragment: tag ?? (fragment.isEmpty ? null : fragment),
    );
  }
}
