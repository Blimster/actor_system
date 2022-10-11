import 'package:actor_system/actor_system.dart';

void main() async {
  final system = ActorSystem();

  final actor1 = await system.createActor(
    Uri.parse('/foo/bar/1'),
    factory: (path) {
      return (context, message) async {
        print('current : ${context.current.path}');
        print('replyTo : ${context.replyTo?.path}');
        print('received: $message');
        final actor =
            await context.lookupActor(Uri.parse('actor://host/foo/bar/2'));
        actor?.send('reply to $message', replyTo: context.current);
      };
    },
  );

  await system.createActor(
    Uri.parse('actor://host/foo/bar/2'),
    factory: (path) {
      return (context, message) {
        print('current : ${context.current.path}');
        print('replyTo : ${context.replyTo?.path}');
        print('received: $message');
      };
    },
  );

  actor1.send('hello world');
}
