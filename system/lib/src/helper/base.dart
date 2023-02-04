import 'package:actor_system/src/system/exceptions.dart';

T getOrSkip<T>(T? value) {
  if (value != null) {
    return value;
  }
  throw SkipMessage();
}

class TypeOf<T> {
  const TypeOf();

  Type get() => T;
}
