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

  WhenLikeActorBuilder isEqual<T>(T message, FutureOr<void> Function(ActorContext context, T message) actor) {
    _conditions.add(_Condition(
      (msg) => msg == message,
      (context, message) => actor(context, message as T),
    ));
    return this;
  }

  WhenLikeActorBuilder isType<T>(FutureOr<void> Function(ActorContext context, T message) actor) {
    final type = TypeOf<T>().get();
    _conditions.add(_Condition(
      (msg) {
        return msg.runtimeType == type;
      },
      (context, message) => actor(context, message as T),
    ));
    return this;
  }

  WhenLikeActorBuilder isTrue(bool Function(Object? message) predicate, Actor actor) {
    _conditions.add(_Condition(predicate, actor));
    return this;
  }

  WhenLikeActorBuilder isInit(Actor actor) {
    _conditions.add(_Condition((msg) => msg == initMsg, actor));
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
