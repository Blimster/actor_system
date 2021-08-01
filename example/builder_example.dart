import 'package:actor_system/actor_system.dart';

class MessageA {
  final String payloadA;

  MessageA(this.payloadA);
}

class MessageB {
  final String payloadB;

  MessageB(this.payloadB);
}

// the actor factory
Actor actorFactory(ActorContext context) {
  // handler for message of type MessageA
  void handleA(MessageA message) {
    print('handleA: ${message.payloadA}');
  }

  // handler for message of type MessageB
  void handleB(MessageB message) {
    print('handleA: ${message.payloadB}');
  }

  // build the actor using type based message handlers
  return TypeBasedMessageActorBuilder()
      .handler(handleA) //
      .handler(handleB) //
      .actor();
}

void main() async {
  // create the actor system
  final system = ActorSystem();

  // create an actor using
  final actor = await system.createActor(Uri(path: '/test/1'), actorFactory);

  // send messages to the actor
  actor.send(MessageA('payload A'));
  actor.send(MessageB('payload B'));
}
