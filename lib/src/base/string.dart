import 'package:logging/logging.dart';

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
