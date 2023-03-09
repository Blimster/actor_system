import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:actor_cluster/src/base.dart';
import 'package:actor_cluster/src/codec.dart';
import 'package:actor_cluster/src/messages/create_actor.dart';
import 'package:actor_cluster/src/messages/lookup_actor.dart';
import 'package:actor_cluster/src/messages/lookup_actors.dart';
import 'package:actor_cluster/src/messages/send_message.dart';
import 'package:actor_cluster/src/protocol.dart';
import 'package:actor_cluster/src/ser_des.dart';
import 'package:actor_cluster/src/stream_reader.dart';
import 'package:actor_system/actor_system.dart';
import 'package:logging/logging.dart';
import 'package:stream_channel/stream_channel.dart';

abstract class Node {
  final String nodeId;
  final String uuid;
  final List<String> tags;
  final bool isSeedNode;
  bool _isClusterInitialized;

  Node(this.nodeId, this.uuid, this.tags, this.isSeedNode, bool isClusterInitialized)
      : _isClusterInitialized = isClusterInitialized;

  bool validateWorkerId(int workerId) => workerId <= workers;

  bool get isLocal;

  int get workers;

  Future<ActorRef> createActor(Uri path, int? mailboxSize);

  Future<ActorRef?> lookupActor(Uri path);

  Future<List<ActorRef>> lookupActors(Uri path);
}

class LocalNode extends Node {
  final Logger _log;
  final SerDes _serDes;
  final Map<int, _WorkerAdapter> _workerAdapters = {};
  final Map<String, RemoteNode> _remoteNodes = {};
  late final Timer _nodeInfoTimer;

  LocalNode(super.nodeId, super.uuid, super.tags, super.isSeedNode, super.isClusterInitialized, this._serDes)
      : _log = Logger('actor_system.cluster.LocalNode:$nodeId') {
    _nodeInfoTimer = Timer.periodic(Duration(seconds: 5), (_) => _publishNodeInfo());
  }

  @override
  bool get isLocal => true;

  @override
  int get workers => _workerAdapters.length;

  void shutdown() {
    _nodeInfoTimer.cancel();
    // TODO close connections and stop workers
  }

  void addRemoteNode(
    String nodeId,
    String host,
    int port,
    String uuid,
    int workers,
    List<String> tags,
    StreamReader reader,
    Sink<List<int>> writer,
    Duration timeout,
    bool isSeedNode,
    bool clusterInitialized,
  ) {
    _log.info('addRemoteNode < nodeId=$nodeId, uuid=$uuid, workers=$workers, timeout=$timeout');
    _remoteNodes[nodeId] = RemoteNode(
      nodeId,
      uuid,
      tags,
      isSeedNode,
      clusterInitialized,
      workers,
      NodeToNodeProtocol(
        'remote@$nodeId',
        MessageChannel(reader, writer, _serDes),
        _serDes,
        timeout,
        _handleClusterInitialized,
        _handleNodeInfo,
        _handleCreateActor,
        _handleLookupActor,
        _handleLookupActors,
        _handleSendMessage,
      ),
      host,
      port,
    );
    _log.info('addRemoteNode >');
  }

  void removeRemoteNode(String nodeId) {
    _log.info('removeRemoteNode < nodeId=$nodeId');
    _remoteNodes.remove(nodeId);
    _log.info('removeRemoteNode >');
  }

  List<RemoteNode> remoteNodes() {
    return _remoteNodes.values.toList();
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
      NodeToWorkerProtocol(
        'worker@$workerId',
        channel,
        _serDes,
        timeout,
        _handleWorkerInfo,
        _handleCreateActor,
        _handleLookupActor,
        _handleLookupActors,
        _handleSendMessage,
      ),
    );
    _log.info('addWorker >');
  }

  bool isLeader() {
    if (!isSeedNode) {
      return false;
    }
    final remoteUuids = _remoteNodes.values.where((e) => e.isSeedNode).map((e) => e.uuid).toList()..sort();
    if (remoteUuids.isEmpty) {
      return true;
    }
    final smallestRemoteUuid = remoteUuids.first;
    return uuid.compareTo(smallestRemoteUuid) < 0;
  }

  void publishClusterInitialized() {
    _isClusterInitialized = true;
    for (var remoteNode in _remoteNodes.values) {
      remoteNode.publishClusterInitialized(nodeId);
    }
  }

  bool isClusterInitialized() {
    if (_isClusterInitialized) {
      return true;
    }
    for (final remoteNode in _remoteNodes.values) {
      if (remoteNode.isClusterInitialized) {
        return true;
      }
    }
    return false;
  }

  @override
  Future<ActorRef> createActor(Uri path, int? mailboxSize) async {
    _log.info('createActor < path=$path, mailboxSize=$mailboxSize');

    final nodeIdFromPath = getNodeId(path.host);
    final workerIdFromPath = getWorkerId(path.host);
    final selectedNodeId = nodeIdFromPath.isNotEmpty ? nodeIdFromPath : _selectNodeId(path.path, path.fragment);

    _log.fine(
        'createActor | nodeIdFromPath=$nodeIdFromPath, workerIdFromPath=$workerIdFromPath, selectedNode=$selectedNodeId');

    if (selectedNodeId == null) {
      throw Exception('no node found for path $path');
    }

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
      remoteNode.actorPaths.add(result.path);
      _log.info('createActor > $result');
      return result;
    } else {
      _log.fine('createActor | local node selected or referenced by path');
      final selectedWorkerId = workerIdFromPath != 0 ? workerIdFromPath : _selectWorkerId(path.path);
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
      workerAdapter.actorPaths.add(result.path);
      _log.info('createActor > $result');
      return result;
    }
  }

  @override
  Future<ActorRef?> lookupActor(Uri path) async {
    _log.info('lookupActor < path=$path');

    final nodeIdFromPath = getNodeId(path.host);
    final workerIdFromPath = getWorkerId(path.host);
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

  @override
  Future<List<ActorRef>> lookupActors(Uri path) async {
    _log.info('lookupActors < path=$path');

    final nodeIdFromPath = getNodeId(path.host);
    final workerIdFromPath = getWorkerId(path.host);
    _log.fine('lookupActors | nodeIdFromPath=$nodeIdFromPath, workerIdFromPath=$workerIdFromPath');

    if (nodeIdFromPath.isEmpty) {
      _log.fine('lookupActors | path does not reference a concrete node');
      final result = <ActorRef>[];
      for (final remoteNode in _remoteNodes.values) {
        _log.fine('lookupActors | lookup on remote node ${remoteNode.nodeId}');
        result.addAll(await remoteNode.protocol
            .lookupActors(actorPath(path.path, system: systemName(remoteNode.nodeId, workerIdFromPath))));
      }
      _log.fine('lookupActors | lookup on local node');
      result.addAll(await lookupActors(actorPath(path.path, system: systemName(nodeId, workerIdFromPath))));
      result.sort((a, b) => a.path.toString().compareTo(b.path.toString()));
      _log.info('lookupActors > $result');
      return result;
    } else if (nodeIdFromPath != nodeId) {
      _log.fine('lookupActors | path references a remote node');
      final remoteNode = _remoteNodes[nodeIdFromPath];
      if (remoteNode == null) {
        _log.fine('lookupActors | node not found');
        throw ArgumentError.value(path.host, 'nodeId', 'node not present');
      }
      final result =
          await remoteNode.lookupActors(actorPath(path.path, system: systemName(nodeIdFromPath, workerIdFromPath)));
      _log.fine('lookupActors > $result');
      return result;
    } else {
      _log.fine('lookupActors | path references the local node');
      if (workerIdFromPath > 0) {
        final workerAdapter = _workerAdapters[workerIdFromPath];
        if (workerAdapter == null) {
          _log.fine('lookupActors | worker not found');
          _log.info('lookupActors > []');
          return [];
        }
        final result = await workerAdapter.protocol.lookupActors(path);
        _log.info('lookupActors > $result');
        return result;
      } else {
        final result = <ActorRef>[];
        for (final workerAdapter in _workerAdapters.values) {
          _log.fine('lookupActors | lookup on worker ${workerAdapter.workerId}');
          result.addAll(await workerAdapter.protocol
              .lookupActors(path.copyWith(system: systemName(nodeId, workerAdapter.workerId))));
        }
        result.sort((a, b) => a.path.toString().compareTo(b.path.toString()));
        _log.info('lookupActors > $result');
        return result;
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

    final nodeIdFromPath = getNodeId(path.host);
    final workerIdFromPath = getWorkerId(path.host);
    final selectedNodeId = nodeIdFromPath.isNotEmpty ? nodeIdFromPath : _selectNodeId(path.path);

    _log.fine(
        'handleCreateActor | nodeIdFromPath=$nodeIdFromPath, workerIdFromPath=$workerIdFromPath, selectedNode=$selectedNodeId');

    if (selectedNodeId == null) {
      return CreateActorResponse(false, 'no node found for path $path');
    }

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
      final selectedWorkerId = workerIdFromPath != 0 ? workerIdFromPath : _selectWorkerId(path.path);
      _log.fine('handleCreateActor | worker $selectedWorkerId selected or referenced by path');
      if (selectedWorkerId == null) {
        return CreateActorResponse(false, 'no worker found for path $path');
      }

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

    final nodeIdFromPath = getNodeId(path.host);
    final workerIdFromPath = getWorkerId(path.host);
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

  Future<LookupActorsResponse> _handleLookupActors(Uri path) async {
    _log.info('handleLookupActors < path=$path');

    final nodeIdFromPath = getNodeId(path.host);
    final workerIdFromPath = getWorkerId(path.host);
    _log.fine('handleLookupActor | nodeIdFromPath=$nodeIdFromPath, workerIdFromPath=$workerIdFromPath');

    if (nodeIdFromPath.isEmpty) {
      _log.fine('handleLookupActors | path does not reference a concrete node');
      final result = <Uri>[];
      for (final remoteNode in _remoteNodes.values) {
        _log.fine('handleLookupActors | lookup on remote node ${remoteNode.nodeId}');
        final actorRefs = await remoteNode.protocol
            .lookupActors(actorPath(path.path, system: systemName(remoteNode.nodeId, workerIdFromPath)));
        result.addAll(actorRefs.map((e) => e.path));
      }
      _log.fine('handleLookupActors | lookup on local node');
      final localLookup = await _handleLookupActors(actorPath(path.path, system: systemName(nodeId, workerIdFromPath)));
      result.addAll(localLookup.paths);
      final response = LookupActorsResponse(result);
      _log.info('handleLookupActors > $response');
      return response;
    } else if (nodeIdFromPath != nodeId) {
      _log.fine('handleLookupActors | path references a remote node');
      final remoteNode = _remoteNodes[nodeIdFromPath];
      if (remoteNode == null) {
        _log.fine('handleLookupActors | remote node not found');
        throw ArgumentError.value(path.host, 'nodeId', 'node not present');
      }
      final actorRefs = await remoteNode.protocol
          .lookupActors(actorPath(path.path, system: systemName(nodeIdFromPath, workerIdFromPath)));
      final response = LookupActorsResponse(actorRefs.map((e) => e.path).toList());
      _log.info('handleLookupActors > $response');
      return response;
    } else {
      _log.fine('handleLookupActors | path references the local node');
      if (workerIdFromPath > 0) {
        final workerAdapter = _workerAdapters[workerIdFromPath];
        if (workerAdapter == null) {
          _log.fine('handleLookupActors | worker not found');
          final response = LookupActorsResponse([]);
          _log.info('handleLookupActors > $response');
          return response;
        }
        final actorRefs = await workerAdapter.protocol
            .lookupActors(actorPath(path.path, system: systemName(nodeId, workerAdapter.workerId)));
        final response = LookupActorsResponse(actorRefs.map((e) => e.path).toList());
        _log.info('handleLookupActors > $response');
        return response;
      } else {
        final result = <Uri>[];
        for (final workerAdapter in _workerAdapters.values) {
          try {
            _log.fine('handleLookupActors | lookup on worker ${workerAdapter.workerId}');
            final actorRefs = await workerAdapter.protocol
                .lookupActors(actorPath(path.path, system: systemName(nodeId, workerAdapter.workerId)));
            result.addAll(actorRefs.map((e) => e.path));
          } catch (e, s) {
            _log.fine('handleLookupActors | $e');
            _log.fine('handleLookupActors | $s');
          }
        }
        final response = LookupActorsResponse(result);
        _log.info('handleLookupActors > $response');
        return response;
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
    final nodeIdFromPath = getNodeId(path.host);
    final workerIdFromPath = getWorkerId(path.host);

    if (nodeIdFromPath.isEmpty) {
      return SendMessageResponse(SendMessageResult.messageNotDelivered, 'invalid actor path: no nodeId');
    }

    if (nodeIdFromPath != nodeId) {
      final remoteNode = _remoteNodes[nodeIdFromPath];
      if (remoteNode == null) {
        return SendMessageResponse(SendMessageResult.messageNotDelivered, 'node not present');
      }
      await remoteNode.protocol.sendMessage(
        actorPath(path.path, system: systemName(nodeIdFromPath, workerIdFromPath)),
        message,
        sender,
        replyTo,
        correlationId,
      );
      return SendMessageResponse(SendMessageResult.success, '');
    } else {
      if (workerIdFromPath == 0) {
        return SendMessageResponse(SendMessageResult.messageNotDelivered, 'invalid actor path: no workerId');
      }
      final workerAdapter =
          _workerAdapters[workerIdFromPath != 0 ? workerIdFromPath : Random().nextInt(_workerAdapters.length) + 1];
      if (workerAdapter == null) {
        return SendMessageResponse(SendMessageResult.messageNotDelivered, 'worker not present');
      }
      try {
        await workerAdapter.protocol.sendMessage(path, message, sender, replyTo, correlationId);
        return SendMessageResponse(SendMessageResult.success, '');
      } catch (e) {
        return SendMessageResponse(SendMessageResult.messageNotDelivered, e.toString());
      }
    }
  }

  void _handleClusterInitialized(String nodeId) {
    _isClusterInitialized = true;
  }

  void _handleNodeInfo(
    String nodeId,
    double load,
    List<Uri> actorsAdded,
    List<Uri> actorsRemoved,
  ) {
    final remoteNode = _remoteNodes[nodeId];
    if (remoteNode != null) {
      remoteNode.load = load;
      remoteNode.actorPaths.addAll(actorsAdded);
      remoteNode.actorPaths.removeAll(actorsRemoved);
    }
  }

  void _handleWorkerInfo(
    int workerId,
    double load,
    List<Uri> actorsAdded,
    List<Uri> actorsRemoved,
  ) {
    final adapter = _workerAdapters[workerId];
    if (adapter != null) {
      adapter.load = load;
      adapter.actorPaths.addAll(actorsAdded);
      adapter.actorPaths.removeAll(actorsRemoved);
    }
    if (actorsAdded.isNotEmpty || actorsRemoved.isNotEmpty) {
      _publishNodeInfo(actorsAdded: actorsAdded, actorsRemoved: actorsRemoved);
    }
  }

  void _publishNodeInfo({List<Uri> actorsAdded = const [], List<Uri> actorsRemoved = const []}) {
    var load = 0.0;
    for (final workerAdapter in _workerAdapters.values) {
      load += workerAdapter.load;
    }
    for (final remoteNode in _remoteNodes.values) {
      remoteNode.protocol.publishNodeInfo(nodeId, load, actorsAdded, actorsRemoved);
    }
  }

  String? _selectNodeId(String targetPath, [String? tag]) {
    _log.fine('selectNodeId < tag=$tag');

    final nodeIdsWithFreePath = _nodeIdsWithFreePath(targetPath);

    final nodeIds = [
      if (tag == null || tag.isEmpty || tags.contains(tag)) nodeId,
      ..._remoteNodes.entries //
          .where((e) => tag == null || tag.isEmpty || e.value.tags.contains(tag))
          .map((e) => e.key),
    ].where((e) => nodeIdsWithFreePath.contains(e)).toList();

    if (nodeIds.isEmpty) {
      _log.fine('selectNodeId > null');
      return null;
    }

    final loads = <String, double>{};
    if (nodeIds.contains(nodeId)) {
      var load = 0.0;
      for (final workerAdapter in _workerAdapters.values) {
        load += workerAdapter.load;
      }
      loads[nodeId] = load;
    }
    for (final remoteNode in _remoteNodes.entries) {
      if (nodeIds.contains(remoteNode.key)) {
        loads[remoteNode.key] = remoteNode.value.load;
      }
    }
    _log.fine('selectNodeId | nodeIds with loads: $loads');

    final highestLoad = loads.entries
        .fold(0.0, (previousValue, element) => element.value > previousValue ? element.value : previousValue);
    if (highestLoad == 0.0) {
      final result = nodeIds[Random().nextInt(nodeIds.length)];
      _log.fine('selectNodeId | selected node by random');
      _log.fine('selectNodeId > $result');
      return result;
    } else {
      String? result;
      var load = 1.0;
      for (final loadEntry in loads.entries) {
        if (loadEntry.value < load) {
          load = loadEntry.value;
          result = loadEntry.key;
        }
      }
      _log.fine('selectNodeId | selected node by load');
      _log.fine('selectNodeId > $result');
      return result;
    }
  }

  Set<String> _nodeIdsWithFreePath(String targetPath) {
    final result = <String>{};

    final workerIds = <String>{};
    for (final workerAdapter in _workerAdapters.values) {
      for (final actorPath in workerAdapter.actorPaths) {
        if (actorPath.path == targetPath) {
          workerIds.add(actorPath.host);
        }
      }
    }
    if (workerIds.length < _workerAdapters.length) {
      result.add(nodeId);
    }

    for (final remoteNode in _remoteNodes.values) {
      final workerIds = <String>{};
      for (final actorPath in remoteNode.actorPaths) {
        if (actorPath.path == targetPath) {
          workerIds.add(actorPath.host);
        }
      }
      if (workerIds.length < remoteNode.workers) {
        result.add(remoteNode.nodeId);
      }
    }

    return result;
  }

  int? _selectWorkerId(String targetPath) {
    final workerIds = <int>{};
    for (final workerAdapter in _workerAdapters.values) {
      var free = true;
      for (final existingPath in workerAdapter.actorPaths) {
        if (existingPath.path == targetPath) {
          free = false;
          break;
        }
      }
      if (free) {
        workerIds.add(workerAdapter.workerId);
      }
    }
    if (workerIds.isEmpty) {
      return null;
    }
    if (workerIds.length == 1) {
      return workerIds.first;
    }

    final randomIndex = Random().nextInt(workerIds.length);
    return workerIds.toList()[randomIndex];
  }
}

class RemoteNode extends Node {
  @override
  final int workers;
  final NodeToNodeProtocol protocol;
  final String host;
  final int port;
  final Set<Uri> actorPaths = {};
  double load = 0.0;

  RemoteNode(
    super.nodeId,
    super.uuid,
    super.tags,
    super.isSeedNode,
    super.clusterInitialized,
    this.workers,
    this.protocol,
    this.host,
    this.port,
  );

  @override
  bool get isLocal => false;

  bool get isClusterInitialized => _isClusterInitialized;

  void publishClusterInitialized(String nodeId) {
    protocol.publishClusterInitialized(nodeId);
  }

  @override
  Future<ActorRef> createActor(Uri path, int? mailboxSize) {
    return protocol.createActor(path, mailboxSize);
  }

  @override
  Future<ActorRef?> lookupActor(Uri path) {
    return protocol.lookupActor(path);
  }

  @override
  Future<List<ActorRef>> lookupActors(Uri path) async {
    return protocol.lookupActors(path);
  }

  Future<void> close() {
    return protocol.close();
  }
}

class _WorkerAdapter {
  final String nodeId;
  final int workerId;
  final Isolate isolate;
  final NodeToWorkerProtocol protocol;
  final Set<Uri> actorPaths = {};
  double load = 0.0;

  _WorkerAdapter(this.nodeId, this.workerId, this.isolate, this.protocol);

  Future<void> stop() async {
    await protocol.close();
    isolate.kill();
  }
}
