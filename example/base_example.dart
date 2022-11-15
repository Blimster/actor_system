import 'dart:isolate';

import 'package:actor_system/actor_system.dart';
import 'package:actor_system/src/base/string.dart';
import 'package:logging/logging.dart';

// actor factory
Actor actorFactory(Uri path) {
  // some actor state
  int calls = 0;

  // a message handler that handles all messages for that actor
  return (ActorContext context, Object? message) {
    // count incoming messages
    calls++;

    // just print the received message
    print("actor ${context.current.path} received message: $message, call: $calls");
  };
}

void main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print(
        '[${record.time.toString().padRight(26, '0')}|${record.level.name.padLeft(7, ' ')}|${Isolate.current.debugName?.abbreviate(10).padLeft(10)}|${record.loggerName.abbreviate(20).padLeft(20)}] ${record.message}');
  });

  // create the actor system
  final actorSystem = ActorSystem();

  // create 2 actors
  final actorRef1 = await actorSystem.createActor(actorPath('/test/1'), factory: actorFactory);
  await actorSystem.createActor(actorPath('/test/2'), factory: actorFactory);

  final actorRef2 = await actorSystem.lookupActor(actorPath('/test/2'));

  // send messages to the actors
  actorRef1.send("text");
  actorRef1.send(1);
  actorRef2?.send("text");
  actorRef2?.send(1);
}
