import 'dart:convert';
import 'dart:typed_data';

import 'package:actor_cluster/actor_cluster.dart';
import 'package:logging/logging.dart';

class StringSerDes implements SerDes {
  @override
  Object? deserialize(Uint8List data) {
    return utf8.decode(data);
  }

  @override
  Uint8List serialize(Object? message) {
    if (message is String) {
      return Uint8List.fromList(utf8.encode(message));
    }
    throw ArgumentError.value(message, 'message', 'not of type String');
  }
}

void initLogging() {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    if (record.loggerName.startsWith('actor://')) {
      print('${record.loggerName} ${record.level} ${record.message}');
    }
  });
}

void main(List<String> args) async {
  final clusterNode = ActorCluster(
    await readClusterConfigFromYaml('example/cluster.yaml'),
    await readNodeConfigFromYaml('example/${args[0]}.yaml'),
    StringSerDes(),
    initWorkerIsolate: (nodeId, workerId) => initLogging(),
  );

  await clusterNode.init(
    addActorFactories: (addActorFactory) {
      addActorFactory(patternMatcher('/actor/1'), (path) {
        return (ActorContext context, Object? msg) async {
          final log = Logger(context.current.path.toString());
          final replyTo = context.replyTo;
          log.info('message: $msg');
          log.info('correlationId: ${context.correlationId}');
          log.info('replyTo: ${replyTo?.path}');
          replyTo?.send(msg);
        };
      });
      addActorFactory(patternMatcher('/actor/2'), (path) {
        return (ActorContext context, Object? msg) async {
          final log = Logger(context.current.path.toString());
          log.info('message: $msg');
          log.info('correlationId: ${context.correlationId}');
          log.info('sender: ${context.sender?.path}');
          final actorRef = await context.lookupActor(actorPath('/actor/3'));
          actorRef?.send(msg);
        };
      });
      addActorFactory(patternMatcher('/actor/3'), (path) {
        return (ActorContext context, Object? msg) {
          final log = Logger(context.current.path.toString());
          log.info('message: $msg');
          log.info('correlationId: ${context.correlationId}');
          log.info('sender: ${context.sender?.path}');
        };
      });
      addActorFactory(patternMatcher('/foo'), (path) {
        return (ActorContext context, Object? msg) {
          final log = Logger(context.current.path.toString());
          log.info('message: $msg');
        };
      });
      addActorFactory(patternMatcher('/bar'), (path) {
        return (ActorContext context, Object? msg) {
          final log = Logger(context.current.path.toString());
          log.info('message: $msg');
        };
      });
    },
    initNode: (CreateActor createActor, List<String> tags) async {
      final actor = await createActor(actorPath('/foo'), 1000);
      await actor.send('test message');
    },
    initCluster: (context) async {
      try {
        await context.createActor(actorPath('/bar', tag: 'foobar'));
        await context.createActor(actorPath('/bar', tag: 'foobar'));
        await context.createActor(actorPath('/bar', tag: 'foobar'));
      } catch (e) {
        print(e);
      }

      final actorRef1 = await context.createActor(Uri.parse('//node1/actor/1'));
      final actorRef2 = await context.createActor(Uri.parse('//node2/actor/2'));
      await context.createActor(Uri.parse('//node1/actor/3'));
      await actorRef1.send('hello cluster actor!', correlationId: '101', replyTo: actorRef2);

      print(await context.lookupActors(actorPath('/')));
    },
  );
}
