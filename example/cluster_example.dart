import 'package:actor_system/actor_cluster.dart';
import 'package:actor_system/src/base/string.dart';
import 'package:logging/logging.dart';

void main(List<String> args) async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print(
        '[${record.time.toString().padRight(26, '0')}|${record.level.name.padLeft(7, ' ')}|${record.loggerName.abbreviate(20).padLeft(20)}] ${record.message}');
  });

  final clusterNode = await ActorCluster(args[0]);
  await clusterNode.init(
    prepareNodeSystem: (system) {
      system.registerFactory(Uri.parse('/foo/'), (path) {
        return (context, msg) {
          print('Received message: $msg');
        };
      });
    },
    afterClusterInit: (context, isLeader) async {
      if (isLeader) {
        final actorRef = await context.createActor(Uri.parse('/foo/'));
        print('actor created on path ${actorRef.path}');
      }
    },
  );
}
