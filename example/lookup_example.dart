import 'package:actor_system/actor_system.dart';

void main() async {
  final system1 = ActorSystem(name: 'system1');
  final system2 = ActorSystem(name: 'system2');

  system1.createActor(
    Uri.parse('/actor'),
    factory: (path) {
      return (context, message) {
        print('system1 received message: $message');
      };
    },
  );

  system2.createActor(
    Uri.parse('/actor'),
    factory: (path) {
      return (context, message) {
        print('system2 received message: $message');
      };
    },
  );

  Future<ActorRef?> externalLookup(Uri uri) async {
    if (uri.host == 'system1') {
      return system1.lookupActor(uri);
    } else if (uri.host == 'system2') {
      return system2.lookupActor(uri);
    }
    return null;
  }

  system1.externalLookup = externalLookup;
  system2.externalLookup = externalLookup;

  final actor = await system1.lookupActor(Uri.parse('//system2/actor'));
  actor?.send('message');
}
