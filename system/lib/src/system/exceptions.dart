import 'package:actor_system/src/system/ref.dart';

/// If an actor throws an instance of this type while
/// processing an message, the actor will not be restarted.
class SkipMessage implements Exception {
  const SkipMessage();
}

/// Thrown by [ActorRef.send] if the message can't be added
/// to actors mailbox.
class MessageNotDelivered implements Exception {
  final String message;
  const MessageNotDelivered(this.message);
}

/// Thrown by [ActorRef.send] if the message can't be added
/// to actors mailbox because it is full.
class MailboxFull extends MessageNotDelivered {
  const MailboxFull() : super('mailbox full');
}

/// Thrown by [ActorRef.send] if the message can't be added
/// to actors mailbox because the actor is stopped.
class ActorStopped extends MessageNotDelivered {
  ActorStopped(Object actorPath, Object? msg, String? cause)
      : super('actor: $actorPath, message: ${msg.runtimeType}, cause: $cause');
}

/// Thrown by [BaseContext.createActor] if no factory was
/// found to create the actor.
class NoFactoryFound implements Exception {
  final Uri _path;
  NoFactoryFound(Uri path) : _path = path;

  String get message => 'No factory found for for path $_path!';

  @override
  String toString() => message;
}
