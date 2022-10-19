import 'package:logging/logging.dart';

extension StringExtension on String {
  /// Abbreviate the string to the given [length].
  String abbreviate(int maxLength) {
    if (this.length > maxLength) {
      return '...' + this.substring(this.length - maxLength + 3);
    }
    return this;
  }

  /// Returns a [Level] from this string. See [Level.LEVELS] for valid strings.
  Level toLogLevel() {
    return Level.LEVELS
        .firstWhere((element) => element.name == this.toUpperCase());
  }
}
