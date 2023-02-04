import 'dart:async';

import 'package:actor_system/actor_system.dart';
import 'package:actor_system/src/helper/base.dart';

class _Condition {
  final bool Function(Object?) predicate;
  final Actor actor;

  _Condition(this.predicate, this.actor);
}

class MessageNotHandledException implements Exception {}

class ActorBuilder {
  final List<_Condition> _conditions = [];

  ActorBuilder isEqual<T>(T message, FutureOr<void> Function(ActorContext context, T message) actor) {
    _conditions.add(_Condition(
      (msg) => msg == message,
      (context, message) => actor(context, message as T),
    ));
    return this;
  }

  ActorBuilder isType<T>(FutureOr<void> Function(ActorContext context, T message) actor) {
    final type = TypeOf<T>().get();
    _conditions.add(_Condition(
      (msg) {
        return msg.runtimeType == type;
      },
      (context, message) => actor(context, message as T),
    ));
    return this;
  }

  ActorBuilder isTrue(bool Function(Object? message) predicate, Actor actor) {
    _conditions.add(_Condition(predicate, actor));
    return this;
  }

  ActorBuilder isInit(Actor actor) {
    _conditions.add(_Condition((msg) => msg == initMsg, actor));
    return this;
  }

  ActorBuilder isShutdown(Actor actor) {
    _conditions.add(_Condition((msg) => msg == shutdownMsg, actor));
    return this;
  }

  Actor orActor(Actor actor) {
    _conditions.add(_Condition((_) => true, actor));
    return _actor();
  }

  Actor orSkip() {
    _conditions.add(_Condition((_) => true, (ctx, msg) => null));
    return _actor();
  }

  Actor orThrow([Object Function()? exception]) {
    _conditions.add(_Condition((_) => true, (ctx, msg) => throw exception?.call() ?? MessageNotHandledException()));
    return _actor();
  }

  Actor _actor() {
    return (ActorContext context, Object? message) async {
      for (final condition in _conditions) {
        if (condition.predicate(message)) {
          return condition.actor(context, message);
        }
      }
      throw StateError('no matching condition found');
    };
  }
}
