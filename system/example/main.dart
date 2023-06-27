import 'package:actor_system/actor_system.dart';

// actor factory
Actor actorFactory(Uri path) {
  // some actor state
  int calls = 0;

  // a message handler that handles all messages for that actor
  return (ActorContext ctx, Object? msg) async {
    // count incoming messages
    calls++;

    // just print the received message
    print(
        "actor: ${ctx.current.path}, sender: ${ctx.sender?.path} message: $msg, correlationId: ${ctx.correlationId}, call: $calls");

    // forward message to the replyTo actor
    await ctx.replyTo?.send(msg);
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
