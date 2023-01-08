import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:actor_system/actor_cluster.dart';
import 'package:actor_system/actor_system.dart';
import 'package:actor_system/src/base/string.dart';
import 'package:actor_system/src/system/actor.dart';
import 'package:logging/logging.dart';

class StringDerDes implements SerDes {
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

void main(List<String> args) async {
  void onLogRecord(LogRecord record) {
    print(
        '[${record.time.toString().padRight(26, '0')}|${record.level.name.padLeft(7, ' ')}|${Isolate.current.debugName?.abbreviate(10).padLeft(10)}|${record.loggerName.abbreviate(20).padLeft(20)}] ${record.message}');
  }

  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen(onLogRecord);

  final clusterNode =
      ActorCluster(await readConfigFromYaml('${args[0]}.yaml'), StringDerDes(), onLogRecord: onLogRecord);
  await clusterNode.init(
    prepareNodeSystem: (registerFactory) {
      registerFactory('/actor/1', (path) {
        return (ActorContext context, Object? msg) async {
          final log = Logger(context.current.path.toString());
          if (msg == initMsg) {
            log.info('received initMessage');
          } else {
            final target = await context.lookupActor(Uri.parse('/actor/2'));
            final replyTo = await context.lookupActor(Uri.parse('/actor/3'));
            log.info('correlationId ${context.correlationId}');
            log.info('forwarding message to ${target?.path}');
            target?.send(msg, sender: context.current, replyTo: replyTo);
          }
        };
      });
      registerFactory('/actor/2', (path) {
        return (ActorContext context, Object? msg) {
          final log = Logger(context.current.path.toString());
          log.info('received message: $msg from ${context.sender?.path}');
          context.replyTo?.send(msg, sender: context.current);
        };
      });
      registerFactory('/actor/3', (path) {
        return (ActorContext context, Object? msg) {
          final log = Logger(context.current.path.toString());
          log.info('received message: $msg from ${context.sender?.path}');
        };
      });
    },
    afterClusterInit: (context, isLeader) async {
      if (isLeader) {
        await context.createActor(Uri.parse('//node2/actor/1'), sendInit: true);
        await context.createActor(Uri.parse('//node3/actor/2'));
        await context.createActor(Uri.parse('//node2/actor/3'));
        final actorRef = await context.lookupActor(Uri.parse('/actor/1'));
        await actorRef?.send('hello cluster actor!', correlationId: '1910');
      }
    },
  );
}
