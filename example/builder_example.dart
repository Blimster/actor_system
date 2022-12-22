import 'package:actor_system/actor_builder.dart';
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
Actor actorFactory(Uri path) {
  // handler for message of type MessageA
  void handleA(_, MessageA message) {
    print('handleA: ${message.payloadA}');
  }

  // handler for message of type MessageB
  void handleB(_, MessageB message) {
    print('handleA: ${message.payloadB}');
  }

  void handleFoo(_, String message) {
    print('expected: foo, received: $message');
  }

  void handleDefault(_, Object? message) {
    print('dflt: $message');
  }

  // build the actor
  return WhenLikeActorBuilder()
      .isEqual('foo', handleFoo)
      .isType<MessageA>(handleA)
      .isType<MessageB>(handleB)
      .deflt(handleDefault)
      .actor();
}

void main() async {
  // create the actor system
  final system = ActorSystem();

  // create an actor
  final actor = await system.createActor(
    Uri(path: '/test/1'),
    factory: actorFactory,
  );

  // send messages to the actor
  actor.send(MessageA('payload A'));
  actor.send(MessageB('payload B'));
}
