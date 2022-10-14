import 'package:actor_system/actor_system.dart';

void main() async {
  final system1 = ActorSystem(name: 'system1');
  final system2 = ActorSystem(name: 'system2');

  Future<ActorRef> externalCreate(Uri path) {
    if (path.host == 'system1') {
      return system1.createActor(path);
    } else if (path.host == 'system2') {
      return system2.createActor(path);
    }
    throw ArgumentError.value(path.host, 'system', 'not found');
  }

  Future<ActorRef?> externalLookup(Uri uri) async {
    if (uri.host == 'system1') {
      return system1.lookupActor(uri);
    } else if (uri.host == 'system2') {
      return system2.lookupActor(uri);
    }
    return null;
  }

  Actor factory(Uri path) {
    if (path.host == 'system1') {
      return (context, message) {
        print('${context.current.path} received: $message');
      };
    } else if (path.host == 'system2') {
      return (context, message) async {
        final actor = await context.lookupActor(Uri.parse('//system1/actor'));
        actor?.send('$message forwarded by ${context.current.path}');
      };
    }
    throw ArgumentError.value(path.host, 'system', 'not found');
  }

  system1.externalCreate = externalCreate;
  system1.externalLookup = externalLookup;
  system1.registerFactory(Uri.parse('/actor'), factory);

  system2.externalCreate = externalCreate;
  system2.externalLookup = externalLookup;
  system2.registerFactory(Uri.parse('/actor'), factory);

  await system1.createActor(
    Uri.parse('//system2/actor'),
    factory: (path) {
      return (context, message) {
        print('system1 received message: $message');
      };
    },
  );

  await system2.createActor(
    Uri.parse('//system1/actor'),
    factory: (path) {
      return (context, message) {
        print('system2 received message: $message');
      };
    },
  );

  final actor = await system1.lookupActor(Uri.parse('//system2/actor'));
  actor?.send('hello world');
}
