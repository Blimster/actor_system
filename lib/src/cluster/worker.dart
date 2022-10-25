import 'dart:isolate';

import 'package:actor_system/actor_system.dart';
import 'package:actor_system/src/cluster/cluster.dart';
import 'package:actor_system/src/cluster/messages/create_actor.dart';
import 'package:actor_system/src/cluster/request_handler.dart';
import 'package:actor_system/src/cluster/worker_adapter.dart';
import 'package:stream_channel/isolate_channel.dart';

class WorkerBootstrapMsg {
  final String nodeId;
  final int workerId;
  final PrepareNodeSystem? prepareNodeSystem;
  final SendPort sendPort;

  WorkerBootstrapMsg(
    this.nodeId,
    this.workerId,
    this.prepareNodeSystem,
    this.sendPort,
  );
}

class Worker {
  final String nodeId;
  final int workerId;
  final ActorSystem actorSystem;
  final IsolateChannel<IsolateMessage> isolateChannel;
  final RequestHandler requestHandler = RequestHandler();

  Worker(this.nodeId, this.workerId, this.actorSystem, this.isolateChannel) {
    requestHandler.onRequest(
      createActorRequestType,
      (CreateActorRequest request) async {
        try {
          final actorRef = await actorSystem.createActor(
            request.path,
            mailboxSize: request.mailboxSize,
            useExistingActor: request.useExistingActor,
          );
          return CreateActorResponse(true, actorRef.path.path);
        } catch (e) {
          return CreateActorResponse(false, e.toString());
        }
      },
    );

    isolateChannel.stream.listen((message) async {
      final response = await requestHandler.handleRequest(
        message.type,
        message.content,
      );
      if (response != null) {
        isolateChannel.sink.add(IsolateMessage(
          message.type,
          message.correlationId,
          response,
        ));
      }
    });
  }
}

Future<void> bootstrapWorker(WorkerBootstrapMsg message) async {
  final receivePort = ReceivePort('${message.nodeId}:${message.workerId}');
  message.sendPort.send(receivePort.sendPort);
  final isolateChannel = IsolateChannel<IsolateMessage>(
    receivePort,
    message.sendPort,
  );

  final actorSystem =
      ActorSystem(name: '${message.nodeId}_${message.workerId}');
  await message.prepareNodeSystem?.call(actorSystem);

  Worker(
    message.nodeId,
    message.workerId,
    actorSystem,
    isolateChannel,
  );
}
