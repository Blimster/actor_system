import 'dart:async';

import 'package:actor_system/src/system/actor.dart';

/// A function that handles a message of an explicit type.
typedef TypeBasedMessageHandler<T> = FutureOr<void> Function(
  ActorContext context,
  T message,
);

/// An actor that handles a set of message types. With 'type', the runtime type
/// of a message is meant.
///
/// A message handler is added for an explicit type of message using the method
/// [TypeBasedMessageActorBuilder.handler]. Subtypes of the type are not handled
/// by the handler.
///
/// The final actor can be created by calling the
/// [TypeBasedMessageActorBuilder.actor] method.
class TypeBasedMessageActorBuilder {
  final Map<Type, dynamic> _handlers = {};

  /// Adds a message handler for an explicit runtime type of a message. Subtypes
  /// of the type will not by that handler.
  TypeBasedMessageActorBuilder handler<T>(TypeBasedMessageHandler<T> handler) {
    final messageType = _TypeOf<T>().get();

    if (_handlers.containsKey(messageType)) {
      throw StateError(
          'a message handler for type $messageType is already registered!');
    }
    _handlers[messageType] = handler;

    return this;
  }

  /// Returns the actor.
  Actor actor() {
    return (ActorContext context, Object? message) {
      final handler = _handlers[message.runtimeType];
      if (handler == null) {
        return null;
      }

      return handler(context, message);
    };
  }
}

class _TypeOf<T> {
  const _TypeOf();

  Type get() => T;
}
