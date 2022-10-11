import 'package:actor_system/actor_system.dart';

void main() async {
  final system = ActorSystem();

  system.registerFactory(
      Uri(path: '/foo/bar/'),
      (path) => (context, message) {
            print('actor ${context.path} received message: $message');
          });

  final actor = await system.createActor(Uri(path: '/foo/bar/'));
  await actor.send('hello world');
}
