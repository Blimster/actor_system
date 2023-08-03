import 'dart:async';
import 'dart:isolate';

import 'package:actor_cluster/src/base.dart';
import 'package:actor_cluster/src/cluster.dart';
import 'package:actor_cluster/src/messages/create_actor.dart';
import 'package:actor_cluster/src/messages/lookup_actor.dart';
import 'package:actor_cluster/src/messages/lookup_actors.dart';
import 'package:actor_cluster/src/messages/send_message.dart';
import 'package:actor_cluster/src/protocol.dart';
import 'package:actor_cluster/src/ser_des.dart';
import 'package:actor_system/actor_system.dart';
import 'package:logging/logging.dart';
import 'package:stream_channel/isolate_channel.dart';

class WorkerBootstrapMsg {
  final String nodeId;
  final int workerId;
  final int timeout;
  final AddActorFactories? addActorFactories;
  final SerDes serDes;
  final SendPort sendPort;
  final Level? logLevel;
  final InitWorkerIsolate? initWorkerIsolate;

  WorkerBootstrapMsg(
    this.nodeId,
    this.workerId,
    this.timeout,
    this.addActorFactories,
    this.serDes,
    this.sendPort,
    this.logLevel,
    this.initWorkerIsolate,
  );
}

class Worker {
  final String nodeId;
  final int workerId;
  final ActorSystem actorSystem;
  final IsolateChannel<ProtocolMessage> channel;
  final SerDes serDes;
  final AddActorFactories? addActorFactories;
  late final WorkerToNodeProtocol protocol;

  Worker(
    this.nodeId,
    this.workerId,
    this.actorSystem,
    this.channel,
    this.serDes,
    this.addActorFactories,
    Duration timeout,
  ) {
    protocol = WorkerToNodeProtocol(
      'worker',
      channel,
      serDes,
      timeout,
      _handleCreateActor,
      _handleLookupActor,
      _handleLookupActors,
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

  Future<LookupActorsResponse> _handleLookupActors(Uri path) async {
    final actorRefs = await actorSystem.lookupActors(path);
    return LookupActorsResponse(actorRefs.map((actorRef) => actorRef.path).toList());
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
        return SendMessageResponse(
            SendMessageResult.actorStopped, ActorStopped.detailed(path, message, 'actor not found').message);
      }
      final senderActor = sender != null ? await actorSystem.lookupActor(sender) : null;
      final replyToActor = replyTo != null ? await actorSystem.lookupActor(replyTo) : null;
      await _runZonedIfRequired(actorRef, message, senderActor, replyToActor, correlationId);
      return SendMessageResponse(SendMessageResult.success, '');
    } on MailboxFull catch (e) {
      return SendMessageResponse(SendMessageResult.mailboxFull, e.toString());
    } on ActorStopped catch (e) {
      return SendMessageResponse(SendMessageResult.actorStopped, e.toString());
    } catch (e) {
      return SendMessageResponse(SendMessageResult.messageNotDelivered, e.toString());
    }
  }

  Future<void> _runZonedIfRequired(
    ActorRef actorRef,
    Object? message,
    ActorRef? senderActor,
    ActorRef? replyToActor,
    String? correlationId,
  ) {
    if (senderActor?.path != null && senderActor?.path.toString() != Zone.current[zoneSenderKey]?.path.toString()) {
      return runZoned(
        () => actorRef.send(message, replyTo: replyToActor, correlationId: correlationId),
        zoneValues: {
          zoneSenderKey: senderActor,
        },
      );
    } else {
      return actorRef.send(message, replyTo: replyToActor, correlationId: correlationId);
    }
  }

  Future<ActorRef> _externalCreateActor(Uri path, int mailboxSize) async {
    return protocol.createActor(path, mailboxSize);
  }

  Future<ActorRef?> _externalLookupActor(Uri path) async {
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

  Future<List<ActorRef>> _externalLookupActors(Uri path) async {
    final result = <ActorRef>[];
    if (path.host.isEmpty) {
      final localRefs = await actorSystem.lookupActors(actorPath(
        path.path,
        system: systemName(nodeId, workerId),
      ));
      result.addAll(localRefs);
    }

    result.addAll(await protocol.lookupActors(path));

    return result;
  }

  Future<void> start() async {
    Timer.periodic(Duration(seconds: 5), (timer) {
      final load = actorSystem.metrics.load;
      protocol.publishWorkerInfo(workerId, load, [], []);
    });
    actorSystem.onActorAdded = (path) {
      final load = actorSystem.metrics.load;
      protocol.publishWorkerInfo(workerId, load, [path], []);
    };
    actorSystem.onActorRemoved = (path) {
      final load = actorSystem.metrics.load;
      protocol.publishWorkerInfo(workerId, load, [], [path]);
    };

    actorSystem.externalCreateActor = _externalCreateActor;
    actorSystem.externalLookupActor = _externalLookupActor;
    actorSystem.externalLookupActors = _externalLookupActors;
    await addActorFactories?.call(actorSystem.addActorFactory);
  }
}

Future<void> bootstrapWorker(WorkerBootstrapMsg message) async {
  if (message.logLevel != null) {
    Logger.root.level = message.logLevel;
  }

  final initWorkerIsolate = message.initWorkerIsolate;
  if (initWorkerIsolate != null) {
    await initWorkerIsolate(message.nodeId, message.workerId);
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
    message.addActorFactories,
    Duration(seconds: message.timeout),
  );
  await worker.start();
}
