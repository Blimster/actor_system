import 'dart:async';

import 'package:actor_system/actor_system.dart';
import 'package:actor_system/src/helper/base.dart';
import 'package:actor_system/src/helper/protocol_controller.dart';

class _Condition {
  final bool Function(ActorContext, Object?) predicate;
  final Actor actor;

  _Condition(this.predicate, this.actor);
}

class MessageNotHandledException implements Exception {}

/// A builder for creating an actor that can handle different types of messages.
class ActorBuilder {
  final List<_Condition> _conditions = [];

  /// Register a protocol controller to handle a sequence of messages. See `ProcolController` for more details.
  ActorBuilder withProtocolController(ProtocolController controller) {
    _conditions.add(_Condition(
      controller.predicate,
      controller.actor,
    ));
    return this;
  }

  /// Handle a message if the message is equal to the given `message` parameter.
  ActorBuilder isEqual<T>(T message, FutureOr<void> Function(ActorContext context, T message) actor) {
    _conditions.add(_Condition(
      (ctx, msg) => msg == message,
      (context, message) => actor(context, message as T),
    ));
    return this;
  }

  /// Handle a message if the message is of type `T`.
  ActorBuilder isType<T>(FutureOr<void> Function(ActorContext ctx, T msg) actor) {
    final type = TypeOf<T>().get();
    _conditions.add(_Condition(
      (ctx, msg) => msg.runtimeType == type,
      (context, message) => actor(context, message as T),
    ));
    return this;
  }

  /// Handle a message if the given `predicate` returns `true`.
  ActorBuilder isTrue(bool Function(Object? message) predicate, Actor actor) {
    _conditions.add(
      _Condition(
        (ctx, msg) => predicate(msg),
        actor,
      ),
    );
    return this;
  }

  /// Handle a message if it is an `initMsg`.
  ActorBuilder isInit(Actor actor) {
    _conditions.add(_Condition(
      (ctx, msg) => msg == initMsg,
      actor,
    ));
    return this;
  }

  /// Handle a message if it is an `shutdownMsg`.
  ActorBuilder isShutdown(Actor actor) {
    _conditions.add(_Condition(
      (ctx, msg) => msg == shutdownMsg,
      actor,
    ));
    return this;
  }

  /// Creates the actor. If no condition is met, the message is delegated to the given `actor`.
  Actor orActor(Actor actor) {
    _conditions.add(_Condition(
      (ctx, msg) => true,
      actor,
    ));
    return _actor();
  }

  /// Creates the actor. If no condition is met, the message is skipped.
  Actor orSkip() {
    _conditions.add(_Condition(
      (ctx, msg) => true,
      (ctx, msg) => null,
    ));
    return _actor();
  }

  /// Creates the actor. If no condition is met, an exception is thrown.
  Actor orThrow([Object Function()? exception]) {
    _conditions.add(_Condition(
      (ctx, msg) => true,
      (ctx, msg) => throw exception?.call() ?? MessageNotHandledException(),
    ));
    return _actor();
  }

  Actor _actor() {
    return (ActorContext ctx, Object? msg) async {
      for (final condition in _conditions) {
        if (condition.predicate(ctx, msg)) {
          return condition.actor(ctx, msg);
        }
      }
      throw StateError('no matching condition found');
    };
  }
}
