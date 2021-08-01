import 'package:actor_system/actor_system.dart';

Actor actorFactory(ActorContext context) {
  int calls = 0;

  return (Object msg) {
    calls++;
    print('$calls: $msg');
    if (msg == 'sync error') {
      // an error not handled by the actor itself. the actor is thrown away and
      // a new instance is created. thus, the state is resetted and the next.
      throw StateError('some sync error');
    } else if (msg == 'async error') {
      return Future(() {
        throw StateError('some async error');
      });
    }
    return null;
  };
}

void main() async {
  final system = ActorSystem();
  final actor = await system.createActor(Uri.parse('/test/1'), actorFactory);
  actor.send('foo');
  actor.send('sync error');
  actor.send('bar');
  actor.send('async error');
  actor.send('foo');
  actor.send('bar');
}
