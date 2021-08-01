import 'package:actor_system/actor_system.dart';

Actor actorFactory(ActorContext context) {
  return (Object message) {
    if (message is int) {
      print(message);
      // if a message of type [int] is processed, a [Future] is returned. the
      // next message sent to the actor will not be processed until the future
      // is completed.
      return Future.delayed(Duration(milliseconds: message));
    } else if (message is String) {
      print(message);
    }
    return null;
  };
}

void main() async {
  final system = ActorSystem();
  final actor = await system.createActor(Uri.parse('/test/1'), actorFactory);
  actor.send(1000);
  actor.send('string message');
}
