import 'dart:async';

import 'package:actor_system/src/system/context.dart';
import 'package:actor_system/src/system/ref.dart';

/// An actor is a function that processes messages. This function should never
/// be called directly. It should only be used as a parameter to
/// [ActorContext.createActor].
///
/// If the processing of a message fails, the actor will be disposed and a new
/// one will be created using the factory.
typedef Actor = FutureOr<void> Function(ActorContext context, Object? message);

/// A factory to create an actor. The given path can be used to determine the
/// type of the actor to create.
typedef ActorFactory = FutureOr<Actor> Function(Uri path);

/// Creates an actor for the given [Uri].
typedef CreateActor = FutureOr<ActorRef> Function(Uri path, int mailboxSize);

/// Looks up an actor by the given [Uri].
typedef LookupActor = FutureOr<ActorRef?> Function(Uri path);

/// Looks up one or more actors by the given [Uri].
typedef LookupActors = FutureOr<List<ActorRef>> Function(Uri path);

/// Called when an actor was added to the system.
typedef OnActorAdded = void Function(Uri path);

/// Called when an actor was removed from the system.
typedef OnActorRemoved = void Function(Uri path);
