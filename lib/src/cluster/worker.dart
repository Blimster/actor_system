import 'dart:isolate';

import 'package:actor_system/actor_system.dart';
import 'package:actor_system/src/base/string.dart';
import 'package:actor_system/src/cluster/base.dart';
import 'package:actor_system/src/cluster/cluster.dart';
import 'package:actor_system/src/cluster/messages/create_actor.dart';
import 'package:actor_system/src/cluster/messages/lookup_actor.dart';
import 'package:actor_system/src/cluster/messages/send_message.dart';
import 'package:actor_system/src/cluster/protocol.dart';
import 'package:actor_system/src/system/context.dart';
import 'package:logging/logging.dart';
import 'package:stream_channel/isolate_channel.dart';

class WorkerBootstrapMsg {
  final String nodeId;
  final int workerId;
  final Level logLevel;
  final PrepareNodeSystem? prepareNodeSystem;
  final SendPort sendPort;

  WorkerBootstrapMsg(
    this.nodeId,
    this.workerId,
    this.logLevel,
    this.prepareNodeSystem,
    this.sendPort,
  );
}

class Worker {
  final String nodeId;
  final int workerId;
  final ActorSystem actorSystem;
  final IsolateChannel<ProtocolMessage> channel;
  final PrepareNodeSystem? prepareNodeSystem;
  late final Protocol protocol;

  Worker(
    this.nodeId,
    this.workerId,
    this.actorSystem,
    this.channel,
    this.prepareNodeSystem,
  ) {
    protocol = Protocol(
      'worker',
      channel,
      Duration(seconds: 5),
      _handleCreateActor,
      _handleLookupActor,
      _handleSendMessage,
    );
  }

  Future<CreateActorResponse> _handleCreateActor(Uri path, int? mailboxSize, bool? useExistingActor) async {
    try {
      final actorRef = await actorSystem.createActor(
        path,
        mailboxSize: mailboxSize,
        useExistingActor: useExistingActor,
      );
      return CreateActorResponse(true, actorRef.path.path);
    } catch (e) {
      return CreateActorResponse(false, e.toString());
    }
  }

  Future<LookupActorResponse> _handleLookupActor(Uri path) async {
    final actorRef = await actorSystem.lookupActor(path);
    return LookupActorResponse(actorRef?.path);
  }

  Future<SendMessageResponse> _handleSendMessage(Uri path, Object? message, Uri? replyTo) async {
    try {
      final actorRef = await actorSystem.lookupActor(path);
      if (actorRef == null) {
        return SendMessageResponse(false, 'actor does not exists');
      }
      await actorRef.send(message);
      return SendMessageResponse(true, '');
    } catch (e) {
      return SendMessageResponse(false, e.toString());
    }
  }

  Future<ActorRef> _externalCreate(Uri path, int mailboxSize, bool useExistingActor) async {
    return protocol.createActor(path, mailboxSize, useExistingActor);
  }

  Future<ActorRef?> _externalLookup(Uri path) async {
    if (path.host.isEmpty) {
      final localRef = await actorSystem.lookupActor(actorPath(
        path.path,
        system: systemName(nodeId, workerId),
      ));
      if (localRef != null) {
        return localRef;
      }
    }

    return protocol.lookupActor(path);
  }

  Future<void> start() async {
    actorSystem.externalCreate = _externalCreate;
    actorSystem.externalLookup = _externalLookup;
    await prepareNodeSystem?.call(actorSystem.registerFactory);
  }
}

Future<void> bootstrapWorker(WorkerBootstrapMsg message) async {
  Logger.root.level = message.logLevel;
  Logger.root.onRecord.listen((record) {
    print(
        '[${record.time.toString().padRight(26, '0')}|${record.level.name.padLeft(7, ' ')}|${Isolate.current.debugName?.abbreviate(10).padLeft(10)}|${record.loggerName.abbreviate(20).padLeft(20)}] ${record.message}');
  });

  final receivePort = ReceivePort('${message.nodeId}:${message.workerId}');
  message.sendPort.send(receivePort.sendPort);
  final isolateChannel = IsolateChannel<ProtocolMessage>(
    receivePort,
    message.sendPort,
  );

  final actorSystem = ActorSystem(
    name: systemName(message.nodeId, message.workerId),
    missingHostHandling: MissingHostHandling.asExternal,
  );

  final worker = Worker(
    message.nodeId,
    message.workerId,
    actorSystem,
    isolateChannel,
    message.prepareNodeSystem,
  );
  await worker.start();
}
