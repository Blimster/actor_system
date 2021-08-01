part of actor_system;

/// An [ActorSystem] is a collection of actors, the can communicate with each
/// other. An actor can only create or lookup actors in the same [ActorSystem].
class ActorSystem extends ActorContext {
  /// Creates a new [ActorSystem].
  ActorSystem() : super._(Uri.parse('/'), {});
}
