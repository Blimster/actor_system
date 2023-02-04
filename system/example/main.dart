import 'package:actor_system/actor_system.dart';

// actor factory
Actor actorFactory(Uri path) {
  // some actor state
  int calls = 0;

  // a message handler that handles all messages for that actor
  return (ActorContext context, Object? message) async {
    // count incoming messages
    calls++;

    // just print the received message
    print("actor: ${context.current.path}, message: $message, correlationId: ${context.correlationId}, call: $calls");

    // forward message to the replyTo actor
    await context.replyTo?.send(message, correlationId: context.correlationId);
  };
}

void main() async {
  // create the actor system
  final actorSystem = ActorSystem();

  // create 2 actors
  final actorRef1 = await actorSystem.createActor(actorPath('/test/1'), factory: actorFactory);
  await actorSystem.createActor(actorPath('/test/2'), factory: actorFactory);

  // lookup an actor
  final actorRef2 = await actorSystem.lookupActor(actorPath('/test/2'));

  // send messages to an actor
  await actorRef1.send('message1', correlationId: '1', replyTo: actorRef2);
  await actorRef1.send('message2', correlationId: '2', replyTo: actorRef2);
}
