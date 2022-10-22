import 'dart:isolate';
import 'dart:typed_data';

import 'package:actor_system/actor_system.dart';
import 'package:actor_system/src/cluster/cluster.dart';
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
  final IsolateChannel<Uint8List> isolateChannel;

  Worker(this.nodeId, this.workerId, this.actorSystem, this.isolateChannel);
}

Future<void> bootstrapWorker(WorkerBootstrapMsg message) async {
  final receivePort = ReceivePort('${message.nodeId}:${message.workerId}');
  message.sendPort.send(receivePort.sendPort);
  final isolateChannel = IsolateChannel<Uint8List>(
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
