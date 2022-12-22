import 'dart:async';

import 'package:actor_system/src/base/type_of.dart';
import 'package:actor_system/src/system/actor.dart';
import 'package:actor_system/src/system/context.dart';

class _Condition {
  final bool Function(Object?) predicate;
  final Actor actor;

  _Condition(this.predicate, this.actor);
}

class WhenLikeActorBuilder {
  final List<_Condition> _conditions = [];
  Actor? _defaultActor;

  WhenLikeActorBuilder isEqual<T>(T message, FutureOr<void> Function(ActorContext, T) actor) {
    _conditions.add(_Condition(
      (m) => m == message,
      (context, message) => actor(context, message as T),
    ));
    return this;
  }

  WhenLikeActorBuilder isType<T>(FutureOr<void> Function(ActorContext, T) actor) {
    final type = TypeOf<T>().get();
    _conditions.add(_Condition(
      (m) {
        return m.runtimeType == type;
      },
      (context, message) => actor(context, message as T),
    ));
    return this;
  }

  WhenLikeActorBuilder deflt(Actor actor) {
    _defaultActor = actor;
    return this;
  }

  Actor actor() {
    return (ActorContext context, Object? message) async {
      for (final condition in _conditions) {
        if (condition.predicate(message)) {
          return condition.actor(context, message);
        }
      }
      if (_defaultActor != null) {
        _defaultActor?.call(context, message);
        return;
      }
      throw ArgumentError.value(message, 'message', 'no matching when condition found');
    };
  }
}