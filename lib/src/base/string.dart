import 'package:logging/logging.dart';

extension StringExtension on String {
  String abbreviate(int maxLength) {
    if (this.length > maxLength) {
      return '...' + this.substring(this.length - maxLength + 3);
    }
    return this;
  }

  Level toLogLevel() {
    return Level.LEVELS.firstWhere((element) => element.name == this);
  }
}
