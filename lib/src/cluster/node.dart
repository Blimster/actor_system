import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:actor_system/src/base/uri.dart';
import 'package:actor_system/src/cluster/base.dart';
import 'package:actor_system/src/cluster/messages/create_actor.dart';
import 'package:actor_system/src/cluster/messages/lookup_actor.dart';
import 'package:actor_system/src/cluster/messages/send_message.dart';
import 'package:actor_system/src/cluster/protocol.dart';
import 'package:actor_system/src/cluster/socket_adapter.dart';
import 'package:actor_system/src/system/ref.dart';
import 'package:stream_channel/stream_channel.dart';

abstract class Node {
  final String nodeId;
  final String uuid;

  Node(this.nodeId, this.uuid);

  bool validateWorkerId(int workerId) {
    return workerId <= workers;
  }

  bool get isLocal;

  int get workers;

  Future<ActorRef> createActor(
    Uri path,
    int? mailboxSize,
    bool? useExistingActor,
  );
}

class LocalNode extends Node {
  final Map<int, _WorkerAdapter> _workerAdapters = {};
  final Map<String, Node> _remoteNodes;

  LocalNode(
    super.nodeId,
    super.uuid,
    this._remoteNodes,
  );

  @override
  bool get isLocal => true;

  @override
  int get workers => _workerAdapters.length;

  void addWorker(int workerId, Isolate isolate, StreamChannel<ProtocolMessage> channel, Duration timeout) {
    assert(!_workerAdapters.containsKey(workerId), 'worker with id $workerId is already added');

    _workerAdapters[workerId] = _WorkerAdapter(
      nodeId,
      workerId,
      isolate,
      Protocol(
        'worker@$workerId',
        channel,
        timeout,
        _handleCreateActor,
        _handleLookupActor,
        _handleSendMessage,
      ),
    );
  }

  @override
  Future<ActorRef> createActor(Uri path, int? mailboxSize, bool? useExistingActor) {
    final nodeId = _getNodeId(path.host);
    final workerId = _getWorkerId(path.host);

    if (nodeId.isNotEmpty && nodeId != this.nodeId) {
      throw ArgumentError.value(path.host, 'nodeId', 'inter-node actors are not supported yet');
    }

    final workerAdapter = _workerAdapters[workerId != 0 ? workerId : Random().nextInt(_workerAdapters.length) + 1];

    if (workerAdapter != null) {
      return workerAdapter.protocol.createActor(
        actorPath(path.path, system: systemName(workerAdapter.nodeId, workerAdapter.workerId)),
        mailboxSize,
        useExistingActor,
      );
    }
    throw Exception('worker with id $workerId not found for node $nodeId');
  }

  Future<void> stopWorkers() async {
    for (final workerAdapter in _workerAdapters.values) {
      await workerAdapter.stop();
    }
    _workerAdapters.clear();
  }

  Future<CreateActorResponse> _handleCreateActor(Uri path, int? mailboxSize, bool? useExistingActor) async {
    final nodeId = _getNodeId(path.host);
    final workerId = _getWorkerId(path.host);

    if (nodeId.isNotEmpty && nodeId != this.nodeId) {
      return CreateActorResponse(false, 'inter-node actors are not supported yet');
    }

    final workerAdapter = _workerAdapters[workerId != 0 ? workerId : Random().nextInt(_workerAdapters.length) + 1];
    if (workerAdapter == null) {
      return CreateActorResponse(false, 'invalid worker id');
    }

    try {
      final result = await workerAdapter.protocol.createActor(
        actorPath(path.path, system: systemName(nodeId, workerId)),
        mailboxSize,
        useExistingActor,
      );
      return CreateActorResponse(true, result.path.path);
    } catch (e) {
      return CreateActorResponse(false, e.toString());
    }
  }

  Future<LookupActorResponse> _handleLookupActor(Uri path) async {
    if (path.host.isEmpty) {
      for (final workerAdapter in _workerAdapters.values) {
        final workerPath = actorPath(path.path, system: systemName(workerAdapter.nodeId, workerAdapter.workerId));
        try {
          final result = await workerAdapter.protocol.lookupActor(workerPath);
          if (result != null) {
            return LookupActorResponse(result.path);
          }
        } catch (e) {
          // ignore
        }
      }
      return LookupActorResponse(null);
    } else {
      final nodeId = _getNodeId(path.host);
      final workerId = _getWorkerId(path.host);

      if (nodeId.isNotEmpty && nodeId != nodeId) {
        return LookupActorResponse(null);
      }

      final workerAdapter = _workerAdapters[workerId != 0 ? workerId : Random().nextInt(_workerAdapters.length) + 1];
      if (workerAdapter == null) {
        return LookupActorResponse(null);
      }

      try {
        final result = await workerAdapter.protocol.lookupActor(path);
        return LookupActorResponse(result?.path);
      } catch (e) {
        return LookupActorResponse(null);
      }
    }
  }

  Future<SendMessageResponse> _handleSendMessage(Uri path, Object? message, Uri? replyTo) async {
    final nodeId = _getNodeId(path.host);
    final workerId = _getWorkerId(path.host);

    if (nodeId.isNotEmpty && nodeId != this.nodeId) {
      return SendMessageResponse(false, 'inter-node actors are not supported yet');
    }

    final workerAdapter = _workerAdapters[workerId != 0 ? workerId : Random().nextInt(_workerAdapters.length) + 1];
    if (workerAdapter == null) {
      return SendMessageResponse(false, 'invalid worker id');
    }

    try {
      await workerAdapter.protocol.sendMessage(path, message, replyTo);
      return SendMessageResponse(true, '');
    } catch (e) {
      return SendMessageResponse(false, e.toString());
    }
  }
}

class RemoteNode extends Node {
  final int workers;
  final SocketAdapter socketAdapter;

  RemoteNode(super.nodeId, super.uuid, this.workers, this.socketAdapter);

  @override
  bool get isLocal => false;

  @override
  Future<ActorRef> createActor(
    Uri path,
    int? mailboxSize,
    bool? useExistingActor,
  ) {
    throw UnimplementedError();
  }
}

String _getNodeId(String host) {
  int separatorIndex = host.lastIndexOf('_');
  if (separatorIndex == -1) {
    return host;
  }
  return host.substring(0, separatorIndex);
}

int _getWorkerId(String host) {
  int separatorIndex = host.lastIndexOf('_');
  if (separatorIndex == -1) {
    return 0;
  }
  return int.parse(host.substring(separatorIndex + 1));
}

class _WorkerAdapter {
  final String nodeId;
  final int workerId;
  final Isolate isolate;
  final Protocol protocol;

  _WorkerAdapter(this.nodeId, this.workerId, this.isolate, this.protocol);

  Future<void> stop() async {
    await protocol.close();
    isolate.kill();
  }
}
