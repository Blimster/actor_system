import 'dart:isolate';

import 'package:actor_system/actor_system.dart';
import 'package:actor_system/src/base/string.dart';
import 'package:logging/logging.dart';

void main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print(
        '[${record.time.toString().padRight(26, '0')}|${record.level.name.padLeft(7, ' ')}|${Isolate.current.debugName?.abbreviate(10).padLeft(10)}|${record.loggerName.abbreviate(20).padLeft(20)}] ${record.message}');
  });

  final system = ActorSystem();

  system.registerFactory(
      RegExp(r'/foo/'),
      (path) => (ActorContext context, Object? message) {
            print('actor ${context.current.path} received message: $message');
          });

  final actor = await system.createActor(Uri(path: '/foo/bar/'));
  await actor.send('hello world');
}
