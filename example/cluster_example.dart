import 'dart:isolate';

import 'package:actor_system/actor_cluster.dart';
import 'package:actor_system/actor_system.dart';
import 'package:actor_system/src/base/string.dart';
import 'package:logging/logging.dart';

void main(List<String> args) async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print(
        '[${record.time.toString().padRight(26, '0')}|${record.level.name.padLeft(7, ' ')}|${Isolate.current.debugName?.abbreviate(10).padLeft(10)}|${record.loggerName.abbreviate(20).padLeft(20)}] ${record.message}');
  });

  final clusterNode = await ActorCluster(args[0]);
  await clusterNode.init(
    prepareNodeSystem: (registerFactory) {
      registerFactory(Uri.parse('/foo'), (path) {
        return (ActorContext context, Object? msg) async {
          final log = Logger(context.current.path.toString());
          final actorRef = await context.lookupActor(Uri.parse('/bar'));
          log.info('${context.current.path} - forwarding message to ${actorRef?.path}');
          actorRef?.send(msg);
        };
      });
      registerFactory(Uri.parse('/bar'), (path) {
        return (ActorContext context, Object? msg) {
          final log = Logger(context.current.path.toString());
          log.info('${context.current.path} - received message: $msg');
        };
      });
    },
    afterClusterInit: (context, isLeader) async {
      if (isLeader) {
        final actorRef1 = await context.createActor(Uri.parse('/foo'));
        await context.createActor(Uri.parse('/bar'));
        await actorRef1.send('hello cluster actor!');
      }
    },
  );
}
