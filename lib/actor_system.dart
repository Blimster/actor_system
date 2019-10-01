library actor_system;

import 'dart:async';
import 'dart:collection';

part 'src/actor.dart';

part 'src/context.dart';

part 'src/system.dart';

class TypeLiteral<T> {
  const TypeLiteral();
  Type get() => T;
}

TypeLiteral typeOf<T>() {
  return TypeLiteral<T>();
}
