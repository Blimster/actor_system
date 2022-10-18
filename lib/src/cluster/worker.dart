import 'dart:isolate';
import 'dart:typed_data';

import 'package:actor_system/actor_system.dart';
import 'package:stream_channel/isolate_channel.dart';

class WorkerBootstrapMsg {
  final String nodeId;
  final int workerId;
  final SendPort sendPort;

  WorkerBootstrapMsg(this.nodeId, this.workerId, this.sendPort);
}

class Worker {
  final String nodeId;
  final int workerId;
  final ActorSystem actorSystem;
  final IsolateChannel<Uint8List> isolateChannel;

  Worker(this.nodeId, this.workerId, this.actorSystem, this.isolateChannel);
}

void bootstrapWorker(WorkerBootstrapMsg message) {
  final receivePort = ReceivePort('${message.nodeId}:${message.workerId}');
  message.sendPort.send(receivePort.sendPort);
  final isolateChannel = IsolateChannel<Uint8List>(
    receivePort,
    message.sendPort,
  );
  Worker(
    message.nodeId,
    message.workerId,
    ActorSystem(name: '${message.nodeId}_${message.workerId}'),
    isolateChannel,
  );
}
