import 'dart:isolate';

import 'package:actor_system/src/base/uri.dart';
import 'package:actor_system/src/cluster/base.dart';
import 'package:actor_system/src/cluster/cluster.dart';
import 'package:actor_system/src/cluster/messages/create_actor.dart';
import 'package:actor_system/src/cluster/messages/lookup_actor.dart';
import 'package:actor_system/src/cluster/messages/send_message.dart';
import 'package:actor_system/src/cluster/protocol.dart';
import 'package:actor_system/src/cluster/ser_des.dart';
import 'package:actor_system/src/system/context.dart';
import 'package:actor_system/src/system/ref.dart';
import 'package:logging/logging.dart';
import 'package:stream_channel/isolate_channel.dart';

class WorkerBootstrapMsg {
  final String nodeId;
  final int workerId;
  final int timeout;
  final PrepareNodeSystem? prepareNodeSystem;
  final SerDes serDes;
  final SendPort sendPort;
  final Level? logLevel;
  final void Function(LogRecord)? onLogRecord;

  WorkerBootstrapMsg(
    this.nodeId,
    this.workerId,
    this.timeout,
    this.prepareNodeSystem,
    this.serDes,
    this.sendPort,
    this.logLevel,
    this.onLogRecord,
  );
}

class Worker {
  final String nodeId;
  final int workerId;
  final ActorSystem actorSystem;
  final IsolateChannel<ProtocolMessage> channel;
  final SerDes serDes;
  final PrepareNodeSystem? prepareNodeSystem;
  late final Protocol protocol;

  Worker(
    this.nodeId,
    this.workerId,
    this.actorSystem,
    this.channel,
    this.serDes,
    this.prepareNodeSystem,
    Duration timeout,
  ) {
    protocol = Protocol(
      'worker',
      channel,
      serDes,
      timeout,
      _handleCreateActor,
      _handleLookupActor,
      _handleSendMessage,
    );
  }

  Future<CreateActorResponse> _handleCreateActor(Uri path, int? mailboxSize) async {
    try {
      final actorRef = await actorSystem.createActor(
        path,
        mailboxSize: mailboxSize,
      );
      return CreateActorResponse(true, actorRef.path.toString());
    } catch (e) {
      return CreateActorResponse(false, e.toString());
    }
  }

  Future<LookupActorResponse> _handleLookupActor(Uri path) async {
    final actorRef = await actorSystem.lookupActor(path);
    return LookupActorResponse(actorRef?.path);
  }

  Future<SendMessageResponse> _handleSendMessage(
    Uri path,
    Object? message,
    Uri? sender,
    Uri? replyTo,
    String? correlationId,
  ) async {
    try {
      final actorRef = await actorSystem.lookupActor(path);
      if (actorRef == null) {
        return SendMessageResponse(false, 'actor does not exists');
      }
      final senderActor = sender != null ? await actorSystem.lookupActor(sender) : null;
      final replyToActor = replyTo != null ? await actorSystem.lookupActor(replyTo) : null;
      await actorRef.send(message, sender: senderActor, replyTo: replyToActor, correlationId: correlationId);
      return SendMessageResponse(true, '');
    } catch (e) {
      return SendMessageResponse(false, e.toString());
    }
  }

  Future<ActorRef> _externalCreate(Uri path, int mailboxSize) async {
    return protocol.createActor(path, mailboxSize);
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
  if (message.logLevel != null) {
    Logger.root.level = message.logLevel;
  }
  if (message.onLogRecord != null) {
    Logger.root.onRecord.listen(message.onLogRecord);
  }

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
    message.serDes,
    message.prepareNodeSystem,
    Duration(seconds: message.timeout),
  );
  await worker.start();
}
