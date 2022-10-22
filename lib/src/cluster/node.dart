import 'dart:async';
import 'dart:math';

import 'package:actor_system/src/cluster/socket_adapter.dart';
import 'package:actor_system/src/cluster/worker_adapter.dart';
import 'package:actor_system/src/system/ref.dart';

abstract class Node {
  final String nodeId;
  final String uuid;
  final int workers;

  Node(this.nodeId, this.uuid, this.workers);

  bool validateWorkerId(int workerId) {
    return workerId <= workers;
  }

  bool get isLocal;

  Future<ActorRef> createActor(
    Uri path,
    int? mailboxSize,
    bool useExistingActor,
  );
}

class LocalNode extends Node {
  final List<WorkerAdapter> workerAdapters;

  LocalNode(
    super.nodeId,
    super.uuid,
    super.workers,
    this.workerAdapters,
  );

  @override
  bool get isLocal => true;

  @override
  Future<ActorRef> createActor(
    Uri path,
    int? mailboxSize,
    bool useExistingActor,
  ) async {
    final workerId = path.port;
    final workerAdapter = workerAdapters[
        workerId != 0 ? workerId - 1 : Random().nextInt(workerAdapters.length)];

    await workerAdapter.createActor(path, mailboxSize, useExistingActor);
    throw UnimplementedError();
  }
}

class RemoteNode extends Node {
  final SocketAdapter socketAdapter;

  RemoteNode(super.nodeId, super.uuid, super.workers, this.socketAdapter);

  @override
  bool get isLocal => false;

  @override
  Future<ActorRef> createActor(
    Uri path,
    int? mailboxSize,
    bool useExistingActor,
  ) {
    throw UnimplementedError();
  }
}
