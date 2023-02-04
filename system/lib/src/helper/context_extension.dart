import 'package:actor_system/actor_system.dart';
import 'package:actor_system/src/helper/base.dart';

extension ActorContextExtension on ActorContext {
  /// Returns the sending actor or throws a [SkipMessage] if null.
  ActorRef get senderOrSkip => getOrSkip(sender);

  /// Returns the actor to reply to or throws a [SkipMessage] if null.
  ActorRef get replyToOrSkip => getOrSkip(replyTo);

  /// Returns the correlation id or throws a [SkipMessage] if null.
  String get correlationIdOrSkip => getOrSkip(correlationId);
}
