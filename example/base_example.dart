import 'package:actor_system/actor_system.dart';

// actor factory
Actor actorFactory(Uri path) {
  // some actor state
  int calls = 0;

  // a message handler that handles all messages for that actor
  return (ActorContext context, Object? message) {
    // count incoming messages
    calls++;

    // just print the received message
    print(
        "actor ${context.current.path} received message: $message, call: $calls");
  };
}

void main() async {
  // create the actor system
  final actorSystem = ActorSystem();

  // create 2 actors
  final actorRef1 = await actorSystem.createActor(actorPath('/test/1'),
      factory: actorFactory);
  final actorRef2 = await actorSystem.createActor(actorPath('/test/2'),
      factory: actorFactory);

  // send messages to the actors
  actorRef1.send("text");
  actorRef1.send(1);
  actorRef2.send("text");
  actorRef2.send(1);
}
