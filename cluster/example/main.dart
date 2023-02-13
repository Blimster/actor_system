import 'dart:convert';
import 'dart:typed_data';

import 'package:actor_cluster/actor_cluster.dart';
import 'package:actor_system/actor_system.dart';
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

void log(LogRecord record) {
  if (record.loggerName.startsWith('actor://')) {
    print('${record.loggerName} ${record.level} ${record.message}');
  }
}

void main(List<String> args) async {
  Logger.root.onRecord.listen(log);

  final clusterNode = ActorCluster(
    await readConfigFromYaml('example/${args[0]}.yaml'),
    StringSerDes(),
    onLogRecord: log,
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
          replyTo?.send(msg, correlationId: context.correlationId, sender: context.current);
        };
      });
      addActorFactory(patternMatcher('/actor/2'), (path) {
        return (ActorContext context, Object? msg) async {
          final log = Logger(context.current.path.toString());
          log.info('message: $msg');
          log.info('correlationId: ${context.correlationId}');
          log.info('sender: ${context.sender?.path}');
          final actorRef = await context.lookupActor(actorPath('/actor/3'));
          actorRef?.send(msg, correlationId: context.correlationId, sender: context.current);
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
    },
    initCluster: (context) async {
      final actorRef1 = await context.createActor(Uri.parse('//node1/actor/1'));
      final actorRef2 = await context.createActor(Uri.parse('//node2/actor/2'));
      await context.createActor(Uri.parse('//node1/actor/3'));
      await actorRef1.send('hello cluster actor!', correlationId: '101', replyTo: actorRef2);
    },
  );
}
