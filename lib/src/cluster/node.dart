import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:actor_system/src/base/uri.dart';
import 'package:actor_system/src/cluster/base.dart';
import 'package:actor_system/src/cluster/codec.dart';
import 'package:actor_system/src/cluster/messages/create_actor.dart';
import 'package:actor_system/src/cluster/messages/lookup_actor.dart';
import 'package:actor_system/src/cluster/messages/send_message.dart';
import 'package:actor_system/src/cluster/protocol.dart';
import 'package:actor_system/src/cluster/ser_des.dart';
import 'package:actor_system/src/cluster/stream_reader.dart';
import 'package:actor_system/src/system/ref.dart';
import 'package:logging/logging.dart';
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

  Future<ActorRef?> lookupActor(Uri path);
}

class LocalNode extends Node {
  final Logger _log;
  final SerDes _serDes;
  final Map<int, _WorkerAdapter> _workerAdapters = {};
  final Map<String, RemoteNode> _remoteNodes = {};

  LocalNode(this._serDes, super.nodeId, super.uuid) : _log = Logger('actor_system.cluster.LocalNode:$nodeId');

  @override
  bool get isLocal => true;

  @override
  int get workers => _workerAdapters.length;

  void addRemoteNode(
      String nodeId, String uuid, int workers, StreamReader reader, Sink<List<int>> writer, Duration timeout) {
    _log.info('addRemoteNode < nodeId=$nodeId, uuid=$uuid, workers=$workers, timeout=$timeout');
    _remoteNodes[nodeId] = RemoteNode(
      nodeId,
      uuid,
      workers,
      Protocol(
        'remote@$nodeId',
        MessageChannel(reader, writer, _serDes),
        _serDes,
        timeout,
        _handleCreateActor,
        _handleLookupActor,
        _handleSendMessage,
      ),
    );
    _log.info('addRemoteNode >');
  }

  void removeRemoteNode(String nodeId) {
    _log.info('removeRemoteNode < nodeId=$nodeId');
    _remoteNodes.remove(nodeId);
    _log.info('removeRemoteNode >');
  }

  bool isConnected(String nodeId) {
    _log.info('isConnected < nodeId=$nodeId');
    final result = _remoteNodes.containsKey(nodeId);
    _log.info('isConnected > $result');
    return result;
  }

  List<String> remoteUuids() {
    _log.info('remoteUuids <');
    final result = _remoteNodes.values.map((e) => e.uuid).toList()..sort();
    _log.info('remoteUuids > $result');
    return result;
  }

  void addWorker(int workerId, Isolate isolate, StreamChannel<ProtocolMessage> channel, Duration timeout) {
    _log.info('addWorker < workderId=$workerId, timeout=$timeout');
    assert(!_workerAdapters.containsKey(workerId), 'worker with id $workerId is already added');

    _workerAdapters[workerId] = _WorkerAdapter(
      nodeId,
      workerId,
      isolate,
      Protocol(
        'worker@$workerId',
        channel,
        _serDes,
        timeout,
        _handleCreateActor,
        _handleLookupActor,
        _handleSendMessage,
      ),
    );
    _log.info('addWorker >');
  }

  @override
  Future<ActorRef> createActor(Uri path, int? mailboxSize, bool? useExistingActor) async {
    _log.info('createActor < path=$path, mailboxSize=$mailboxSize, useExistingActor=$useExistingActor');

    final nodeIdFromPath = _getNodeId(path.host);
    final workerIdFromPath = _getWorkerId(path.host);
    final selectedNodeId = nodeIdFromPath.isNotEmpty ? nodeIdFromPath : _selectNodeId();

    _log.fine(
        'createActor | nodeIdFromPath=$nodeIdFromPath, workerIdFromPath=$workerIdFromPath, selectedNode=$selectedNodeId');

    if (selectedNodeId != nodeId) {
      _log.fine('createActor | remote node selected or referenced by path');
      final remoteNode = _remoteNodes[selectedNodeId];
      if (remoteNode == null) {
        throw ArgumentError.value(path.host, 'nodeId', 'node not present');
      }
      _log.fine('createActor | remote node found. delegating call to remote node...');
      final result = await remoteNode.protocol.createActor(
        actorPath(path.path, system: systemName(selectedNodeId, workerIdFromPath)),
        mailboxSize,
      );
      _log.info('createActor > $result');
      return result;
    } else {
      _log.fine('createActor | local node selected or referenced by path');
      final selectedWorkerId = workerIdFromPath != 0 ? workerIdFromPath : Random().nextInt(_workerAdapters.length) + 1;
      _log.fine('createActor | worker $selectedWorkerId selected or referenced by path');
      final workerAdapter = _workerAdapters[selectedWorkerId];
      if (workerAdapter == null) {
        throw Exception('worker with id $workerIdFromPath not found for node $selectedNodeId');
      }
      _log.fine('createActor | worker found. delegating call to worker...');
      final result = await workerAdapter.protocol.createActor(
        actorPath(path.path, system: systemName(workerAdapter.nodeId, workerAdapter.workerId)),
        mailboxSize,
      );
      _log.info('createActor > $result');
      return result;
    }
  }

  @override
  Future<ActorRef?> lookupActor(Uri path) async {
    _log.info('lookupActor < path=$path');

    final nodeIdFromPath = _getNodeId(path.host);
    final workerIdFromPath = _getWorkerId(path.host);
    _log.fine('lookupActor | nodeIdFromPath=$nodeIdFromPath, workerIdFromPath=$workerIdFromPath');

    if (nodeIdFromPath.isEmpty) {
      _log.fine('lookupActor | path does not reference a concrete node');
      for (final remoteNode in _remoteNodes.values) {
        _log.fine('lookupActor | lookup on remote node ${remoteNode.nodeId}');
        final result = await remoteNode.protocol
            .lookupActor(actorPath(path.path, system: systemName(remoteNode.nodeId, workerIdFromPath)));
        if (result != null) {
          _log.info('lookupActor > $result');
          return result;
        }
      }
      _log.fine('lookupActor | lookup on local node');
      final result = await lookupActor(actorPath(path.path, system: systemName(nodeId, workerIdFromPath)));
      _log.info('lookupActor > $result');
      return result;
    } else if (nodeIdFromPath != nodeId) {
      _log.fine('lookupActor | path references a remote node');
      final remoteNode = _remoteNodes[nodeIdFromPath];
      if (remoteNode == null) {
        _log.fine('lookupActor | node not found');
        throw ArgumentError.value(path.host, 'nodeId', 'node not present');
      }
      final result =
          await remoteNode.lookupActor(actorPath(path.path, system: systemName(nodeIdFromPath, workerIdFromPath)));
      _log.fine('lookupActor > $result');
      return result;
    } else {
      _log.fine('lookupActor | path references the local node');
      if (workerIdFromPath > 0) {
        final workerAdapter = _workerAdapters[workerIdFromPath];
        if (workerAdapter == null) {
          _log.fine('lookupActor | worker not found');
          _log.info('lookupActor > null');
          return null;
        }
        final result = await workerAdapter.protocol.lookupActor(path);
        _log.info('lookupActor > $result');
        return result;
      } else {
        for (final workerAdapter in _workerAdapters.values) {
          _log.fine('lookupActor | lookup on worker ${workerAdapter.workerId}');
          final result = await workerAdapter.protocol.lookupActor(path);
          if (result != null) {
            _log.info('lookupActor > $result');
            return result;
          }
        }
        _log.info('lookupActor > null');
        return null;
      }
    }
  }

  Future<void> stopWorkers() async {
    for (final workerAdapter in _workerAdapters.values) {
      await workerAdapter.stop();
    }
    _workerAdapters.clear();
  }

  Future<CreateActorResponse> _handleCreateActor(Uri path, int? mailboxSize) async {
    _log.info('handleCreateActor < path=$path, mailboxSize=$mailboxSize');

    final nodeIdFromPath = _getNodeId(path.host);
    final workerIdFromPath = _getWorkerId(path.host);
    final selectedNodeId = nodeIdFromPath.isNotEmpty ? nodeIdFromPath : _selectNodeId();

    _log.fine(
        'handleCreateActor | nodeIdFromPath=$nodeIdFromPath, workerIdFromPath=$workerIdFromPath, selectedNode=$selectedNodeId');

    if (selectedNodeId != nodeId) {
      _log.fine('handleCreateActor | remote node selected or referenced by path');

      final remoteNode = _remoteNodes[selectedNodeId];
      if (remoteNode == null) {
        throw ArgumentError.value(path.host, 'nodeId', 'node not present');
      }
      try {
        _log.fine('handleCreateActor | remote node found. delegating call to remote node...');
        final result = await remoteNode.protocol.createActor(
          actorPath(path.path, system: systemName(selectedNodeId, workerIdFromPath)),
          mailboxSize,
        );
        _log.fine('handleCreateActor | actor created with path ${result.path}');
        return CreateActorResponse(true, result.path.toString());
      } catch (e, s) {
        _log.warning('handleCreateActor | $e');
        _log.warning('handleCreateActor | $s');
        final result = CreateActorResponse(false, e.toString());
        _log.info('handleCreateActor > $result');
        return result;
      }
    } else {
      _log.fine('handleCreateActor | local node selected or referenced by path');
      final selectedWorkerId = workerIdFromPath != 0 ? workerIdFromPath : Random().nextInt(_workerAdapters.length) + 1;
      _log.fine('handleCreateActor | worker $selectedWorkerId selected or referenced by path');
      final workerAdapter = _workerAdapters[selectedWorkerId];
      if (workerAdapter == null) {
        return CreateActorResponse(false, 'invalid worker id');
      }

      try {
        _log.fine('handleCreateActor | worker found. delegating call to worker...');
        final actorRef = await workerAdapter.protocol.createActor(
          actorPath(path.path, system: systemName(selectedNodeId, selectedWorkerId)),
          mailboxSize,
        );
        final result = CreateActorResponse(true, actorRef.path.toString());
        _log.info('handleCreateActor > $result');
        return result;
      } catch (e, s) {
        _log.warning('handleCreateActor | $e');
        _log.warning('handleCreateActor | $s');
        final result = CreateActorResponse(false, e.toString());
        _log.info('handleCreateActor > $result');
        return result;
      }
    }
  }

  Future<LookupActorResponse> _handleLookupActor(Uri path) async {
    _log.info('handleLookupActor < path=$path');

    final nodeIdFromPath = _getNodeId(path.host);
    final workerIdFromPath = _getWorkerId(path.host);
    _log.fine('handleLookupActor | nodeIdFromPath=$nodeIdFromPath, workerIdFromPath=$workerIdFromPath');

    if (nodeIdFromPath.isEmpty) {
      _log.fine('handleLookupActor | path does not reference a concrete node');
      for (final remoteNode in _remoteNodes.values) {
        _log.fine('handleLookupActor | lookup on remote node ${remoteNode.nodeId}');
        final actorRef = await remoteNode.protocol
            .lookupActor(actorPath(path.path, system: systemName(remoteNode.nodeId, workerIdFromPath)));
        if (actorRef != null) {
          final result = LookupActorResponse(actorRef.path);
          _log.info('handleLookupActor > $result');
          return result;
        }
      }
      _log.fine('handleLookupActor | lookup on local node');
      final result = await _handleLookupActor(actorPath(path.path, system: systemName(nodeId, workerIdFromPath)));
      _log.info('handleLookupActor > $result');
      return result;
    } else if (nodeIdFromPath != nodeId) {
      _log.fine('handleLookupActor | path references a remote node');
      final remoteNode = _remoteNodes[nodeIdFromPath];
      if (remoteNode == null) {
        _log.fine('handleLookupActor | remote node not found');
        throw ArgumentError.value(path.host, 'nodeId', 'node not present');
      }
      final actorRef = await remoteNode.protocol
          .lookupActor(actorPath(path.path, system: systemName(nodeIdFromPath, workerIdFromPath)));
      final result = LookupActorResponse(actorRef?.path);
      _log.fine('handleLookupActor > $result');
      return result;
    } else {
      _log.fine('handleLookupActor | path references the local node');
      if (workerIdFromPath > 0) {
        final workerAdapter = _workerAdapters[workerIdFromPath];
        if (workerAdapter == null) {
          _log.fine('lookupActor | worker not found');
          final result = LookupActorResponse(null);
          _log.info('handleLookupActor > $result');
          return result;
        }
        final actorRef = await workerAdapter.protocol
            .lookupActor(actorPath(path.path, system: systemName(nodeId, workerAdapter.workerId)));
        final result = LookupActorResponse(actorRef?.path);
        _log.info('handleLookupActor > $result');
        return result;
      } else {
        for (final workerAdapter in _workerAdapters.values) {
          try {
            _log.fine('handleLookupActor | lookup on worker ${workerAdapter.workerId}');
            final actorRef = await workerAdapter.protocol
                .lookupActor(actorPath(path.path, system: systemName(nodeId, workerAdapter.workerId)));
            if (actorRef != null) {
              final result = LookupActorResponse(actorRef.path);
              _log.info('handleLookupActor > $result');
              return result;
            }
          } catch (e, s) {
            _log.fine('handleLookupActor | $e');
            _log.fine('handleLookupActor | $s');
            final result = LookupActorResponse(null);
            _log.info('handleLookupActor > $result');
            return result;
          }
        }
        final result = LookupActorResponse(null);
        _log.info('handleLookupActor > $result');
        return result;
      }
    }
  }

  Future<SendMessageResponse> _handleSendMessage(
    Uri path,
    Object? message,
    Uri? sender,
    Uri? replyTo,
    String? correlationId,
  ) async {
    final nodeIdFromPath = _getNodeId(path.host);
    final workerIdFromPath = _getWorkerId(path.host);

    if (nodeIdFromPath.isEmpty) {
      return SendMessageResponse(false, 'invalid actor path: no nodeId');
    }

    if (nodeIdFromPath != nodeId) {
      final remoteNode = _remoteNodes[nodeIdFromPath];
      if (remoteNode == null) {
        return SendMessageResponse(false, 'node not present');
      }
      await remoteNode.protocol.sendMessage(
        actorPath(path.path, system: systemName(nodeIdFromPath, workerIdFromPath)),
        message,
        sender,
        replyTo,
        correlationId,
      );
      return SendMessageResponse(true, '');
    } else {
      if (workerIdFromPath == 0) {
        return SendMessageResponse(false, 'invalid actor path: no workerId');
      }
      final workerAdapter =
          _workerAdapters[workerIdFromPath != 0 ? workerIdFromPath : Random().nextInt(_workerAdapters.length) + 1];
      if (workerAdapter == null) {
        return SendMessageResponse(false, 'worker not present');
      }
      try {
        await workerAdapter.protocol.sendMessage(path, message, sender, replyTo, correlationId);
        return SendMessageResponse(true, '');
      } catch (e) {
        return SendMessageResponse(false, e.toString());
      }
    }
  }

  String _selectNodeId() {
    final nodeIds = [
      nodeId,
      ..._remoteNodes.keys,
    ];
    return nodeIds[Random().nextInt(nodeIds.length)];
  }
}

class RemoteNode extends Node {
  @override
  final int workers;
  final Protocol protocol;

  RemoteNode(super.nodeId, super.uuid, this.workers, this.protocol);

  @override
  bool get isLocal => false;

  @override
  Future<ActorRef> createActor(Uri path, int? mailboxSize, bool? useExistingActor) {
    return protocol.createActor(path, mailboxSize);
  }

  @override
  Future<ActorRef?> lookupActor(Uri path) {
    return protocol.lookupActor(path);
  }

  Future<void> close() {
    return protocol.close();
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
