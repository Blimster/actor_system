import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:actor_cluster/src/base.dart';
import 'package:actor_cluster/src/config.dart';
import 'package:actor_cluster/src/context.dart';
import 'package:actor_cluster/src/messages/handshake.dart';
import 'package:actor_cluster/src/node.dart';
import 'package:actor_cluster/src/ser_des.dart';
import 'package:actor_cluster/src/socket_adapter.dart';
import 'package:actor_cluster/src/worker.dart';
import 'package:actor_system/actor_system.dart';
import 'package:logging/logging.dart';
import 'package:stream_channel/isolate_channel.dart';
import 'package:uuid/uuid.dart';

/// Called after all seed nodes are up and connected. This
/// callback is only called on the node elected as leader.
typedef InitCluster = FutureOr<void> Function(ClusterContext context);

/// Called after the node is up and all workers are started.
/// The provided [createActor] function can only create actors
/// on the local node.
typedef InitNode = FutureOr<void> Function(
  Future<ActorRef> Function(Uri path, int? mailboxSize) createActor,
  List<String> tags,
);

/// To be called by the implementor of [AddActorFactories]
/// to add factories.
typedef AddActorFactory = void Function(PathMatcher pathMatcher, ActorFactory factory);

/// Called to preprare the actor system of every worker of
///  a node. Use this callback to add actor factories.
typedef AddActorFactories = FutureOr<void> Function(AddActorFactory addActorFactory);

enum NodeState {
  created,
  starting,
  started,
  connecting,
  connected,
  stopped,
}

class ClosedConnectionHandler {
  final void Function(String?) handleClosedConnection;
  String? nodeId;

  ClosedConnectionHandler(this.handleClosedConnection);

  void call() {
    handleClosedConnection(nodeId);
  }
}

class ActorCluster {
  final _log = Logger('actor_system.cluster.ActorClusterNode');
  final SerDes _serDes;
  final ClusterConfig _clusterConfig;
  final NodeConfig _nodeConfig;
  final Level? _logLevel;
  final void Function(LogRecord)? _onLogRecord;
  final Map<String, ConfigNode> _missingAdditionalNodes = {};
  late final LocalNode _localNode;
  InitNode? _initNode;
  InitCluster? _initCluster;
  AddActorFactories? _addActorFactories;
  NodeState _state = NodeState.created;
  ServerSocket? _serverSocket;
  Timer? _connectTimer;

  ActorCluster(
    ClusterConfig clusterConfig,
    NodeConfig nodeConfig,
    SerDes serDes, {
    Level? logLevel,
    void Function(LogRecord)? onLogRecord,
  })  : _clusterConfig = clusterConfig,
        _nodeConfig = nodeConfig,
        _serDes = serDes,
        _logLevel = logLevel,
        _onLogRecord = onLogRecord;

  NodeState get state => _state;

  Future<void> init({
    InitNode? initNode,
    InitCluster? initCluster,
    AddActorFactories? addActorFactories,
  }) async {
    _log.info('init < initNode=$initNode, initCluster=$initCluster, addActorFactories=$addActorFactories');

    _log.info('init | state is ${_state.name}');
    if (_state != NodeState.created) {
      throw StateError('node is not in state ${NodeState.created.name}');
    }

    _initNode = initNode;
    _initCluster = initCluster;
    _addActorFactories = addActorFactories;

    _state = NodeState.starting;
    _log.info('init | set state to ${_state.name}');

    final uuid = Uuid().v4();

    // read config
    _log.info('init | configuration entries:');
    _log.info('init | - cluster:');
    _log.info('init |   - nodes: ${_clusterConfig.nodes}');
    _log.info('init |   - tags: ${_clusterConfig.tags}');
    _log.info('init |   - timeout: ${_clusterConfig.timeout}');
    _log.info('init |   - secret: ${'*' * _clusterConfig.secret.length}');
    _log.info('init | - node:');
    _log.info('init |   - node: ${_nodeConfig.node}');
    _log.info('init |   - workers: ${_nodeConfig.workers}');
    _log.info('init |   - tags: ${_nodeConfig.tags}');
    _log.info('init |   - uuid: $uuid');

    // validate config
    if (_nodeConfig.node.id == localSystem) {
      throw ArgumentError.value(
        'localNode.id',
        _nodeConfig.node.id,
        '"$localSystem" is reserved.',
      );
    }
    final uri = Uri.tryParse('//${_nodeConfig.node.id}:8000/');
    if (uri == null) {
      throw ArgumentError.value(
        'localNode.id',
        _nodeConfig.node.id,
        'must be a valid host in an URI',
      );
    }

    _localNode = LocalNode(
      _nodeConfig.node.id,
      uuid,
      _nodeConfig.tags,
      _isSeedNode(_nodeConfig.node.id),
      false,
      _serDes,
    );

    // bind server socket
    _log.info('init | binding server socket to ${_nodeConfig.node}...');
    final serverSocket = await ServerSocket.bind(
      _nodeConfig.node.host,
      _nodeConfig.node.port,
    );
    _serverSocket = serverSocket;

    // wait for new connections
    serverSocket.listen(_handleNewConnection);
    _log.info('init | server socket bound and waiting for connections');

    // start node workers
    await _startNode();

    // periodically connect to other seed nodes
    if (_hasMissingNodes()) {
      _startConnectingToMissingNodes();
    } else {
      _stopConnectingToMissingNodes();
      await _initializeCluster();
    }

    _log.info('init >');
  }

  Future<void> shutdown() async {
    _log.info('shutdown <');
    await _serverSocket?.close();
    _log.info('shutdown | server socket closed');
    _stopConnectingToMissingNodes();
    _log.info('shutdown | connecting to missing nodes stopped');
    await _stopWorkers();
    _log.info('shutdown | workers stopped');
    _state = NodeState.stopped;
    _log.info('shutdown | set state to ${_state.name}');
    _log.info('shutdown >');
  }

  Future<void> _handleNewConnection(Socket socket) async {
    final timeout = 3;
    _log.info('handleNewConnection < socket=${socket.address}');
    final timer = Timer(Duration(seconds: timeout), () => _handleTimedOutConnection(timeout, socket));
    try {
      final closedConnectionHandler = ClosedConnectionHandler(_handleClosedConnection);
      final socketAdapter = SocketAdapter(socket);
      socketAdapter.bind(onDone: closedConnectionHandler);

      final message = await socketAdapter.receiveData();

      // received a message, cancel the timer
      timer.cancel();

      // check message type
      if (message.type != handshakeRequestType) {
        throw StateError('invalid handshake message type. message type=${message.type}');
      }

      // read message content
      final handshakeRequest = HandshakeRequest.fromJson(json.decode(message.content));
      _log.info('handleNewConnection | handshake request received');
      _log.info(
          'handleNewConnection | nodeId=${handshakeRequest.node.nodeId}, host=${handshakeRequest.node.host}, port=${handshakeRequest.node.port}');

      // check secret
      if (handshakeRequest.secret != _clusterConfig.secret) {
        throw StateError('invalid handshake secret');
      }
      _log.info('handleNewConnection | secret is valid');

      // check seed node ids
      final localSeedNodeIds = _clusterConfig.nodes.map((e) => e.id).toSet();
      final remoteSeedNodeIds = handshakeRequest.seedNodeIds.toSet();
      if (localSeedNodeIds.length != remoteSeedNodeIds.length || !localSeedNodeIds.containsAll(remoteSeedNodeIds)) {
        throw StateError('seed node mismatch: local=$localSeedNodeIds, remote=$remoteSeedNodeIds');
      }
      _log.info('handleNewConnection | seed node ids are matching');

      // check if node is already connected
      if (_localNode.isConnected(handshakeRequest.node.nodeId)) {
        throw StateError('node already connected');
      }

      // check same node
      if (handshakeRequest.node.nodeId == _nodeConfig.node.id) {
        throw StateError('same node id');
      }

      // send handshake response
      await socketAdapter.sendMessage(SocketMessage(
        handshakeResponseType,
        json.encode(HandshakeResponse(
          handshakeRequest.correlationId,
          HandshakeNode(_nodeConfig.node.id, _nodeConfig.node.host, _nodeConfig.node.port),
          _localNode.uuid,
          _nodeConfig.workers,
          _nodeConfig.tags,
          _localNode.remoteNodes().map((e) => HandshakeNode(e.nodeId, e.host, e.port)).toList(),
          _localNode.isClusterInitialized(),
        ).toJson()),
      ));

      if (!_localNode.isConnected(handshakeRequest.node.nodeId)) {
        // store connection
        _localNode.addRemoteNode(
          handshakeRequest.node.nodeId,
          handshakeRequest.node.host,
          handshakeRequest.node.port,
          handshakeRequest.uuid,
          handshakeRequest.workers,
          handshakeRequest.tags,
          socketAdapter.streamReader,
          socketAdapter.socket,
          Duration(seconds: _clusterConfig.timeout),
          _isSeedNode(handshakeRequest.node.nodeId),
          handshakeRequest.clusterInitialized,
        );

        // handle closed connection
        closedConnectionHandler.nodeId = handshakeRequest.node.nodeId;
      } else {
        _log.info('handleNewConnection | remote node already present. closing socket...');
        socket.destroy();
        _log.info('handleNewConnection | socket closed');
      }

      if (!_hasMissingNodes()) {
        _stopConnectingToMissingNodes();
        await _initializeCluster();
      }
    } catch (e, s) {
      timer.cancel();
      _log.info('handleNewConnection | $e');
      _log.info('handleNewConnection | $s');
      _log.info('handleNewConnection | closing socket...');
      socket.destroy();
      _log.info('handleNewConnection | socket closed');
    }
    _log.info('handleNewConnection >');
  }

  void _handleTimedOutConnection(int timeout, Socket socket) {
    _log.info('handleTimedOutConnection < timeout=$timeout, socket=${socket.addressToString()}');
    _log.info('handleTimedOutConnection | closing socket...');
    socket.destroy();
    _log.info('handleTimedOutConnection | socket closed');
    _log.info('handleTimedOutConnection >');
  }

  void _handleClosedConnection(String? nodeId) {
    _log.info('handleClosedConnection < nodeId=$nodeId');
    if (nodeId != null) {
      _localNode.removeRemoteNode(nodeId);
      _log.info('handleClosedConnection | remote node for nodeId=$nodeId removed');
    }
    if (_hasMissingNodes()) {
      _startConnectingToMissingNodes();
    }
    _log.info('handleClosedConnection >');
  }

  Future<void> _connectToNodes() async {
    _log.info('connectToNodes <');
    final missingSeedNodes = _missingSeedNodes();
    final missingAdditionalNodes = _missingAdditionalNodes.values.toList();
    final missingNodes = missingSeedNodes + missingAdditionalNodes;
    _log.info('connectToNodes | missingSeedNodes=${missingSeedNodes.map((e) => e.id).toList()}');
    _log.info('connectToNodes | missingAdditionalNodes=${missingAdditionalNodes.map((e) => e.id).toList()}');
    for (final node in missingNodes) {
      Socket? socketToClose;
      try {
        _log.info('connectToNodes | trying to connect to node ${node.id}');

        // open socket connection
        final closedConnectionHandler = ClosedConnectionHandler(_handleClosedConnection);
        final socket = await Socket.connect(node.host, node.port);
        final socketAdapter = SocketAdapter(socket);
        socketAdapter.bind(onDone: closedConnectionHandler);
        socketToClose = socket;
        _log.info('connectToNodes | connection established');

        // send handshake request
        _log.info('connectToNodes | sending handshake request...');
        final correlationId = Uuid().v4();
        socketAdapter.sendMessage(SocketMessage(
          handshakeRequestType,
          json.encode(HandshakeRequest(
            correlationId,
            _clusterConfig.nodes.map((e) => e.id).toList(),
            _clusterConfig.secret,
            HandshakeNode(_nodeConfig.node.id, _nodeConfig.node.host, _nodeConfig.node.port),
            _localNode.uuid,
            _nodeConfig.workers,
            _nodeConfig.tags,
            _localNode.isClusterInitialized(),
          ).toJson()),
        ));

        // read response type and check it
        _log.info('connectToNodes | waiting for handshake response...');
        final response = await socketAdapter.receiveData();
        if (response.type != handshakeResponseType) {
          throw StateError('invalid handshake response type');
        }

        // read handshake response
        final handshakeResponse = HandshakeResponse.fromJson(json.decode(response.content));
        _log.info('connectToNodes | received handshake response');

        // check correlation id
        if (handshakeResponse.correlationId != correlationId) {
          throw StateError('invalid handshake response correlation id (${handshakeResponse.correlationId})');
        }

        // check node id
        if (handshakeResponse.node.nodeId != node.id) {
          throw StateError('invalid handshake response node id (${handshakeResponse.node.nodeId})');
        }

        // check uuid
        if (handshakeResponse.uuid == _localNode.uuid) {
          throw StateError('remote node has same uuid');
        }

        for (final additionalNode in handshakeResponse.connectedAdditionalNodes) {
          if (!_missingAdditionalNodes.containsKey(additionalNode.nodeId) &&
              !_localNode.isConnected(additionalNode.nodeId)) {
            _missingAdditionalNodes[additionalNode.nodeId] =
                ConfigNode(additionalNode.host, additionalNode.port, additionalNode.nodeId);
          }
        }

        // store connection
        if (!_localNode.isConnected(handshakeResponse.node.nodeId)) {
          _localNode.addRemoteNode(
            handshakeResponse.node.nodeId,
            handshakeResponse.node.host,
            handshakeResponse.node.port,
            handshakeResponse.uuid,
            handshakeResponse.workers,
            handshakeResponse.tags,
            socketAdapter.streamReader,
            socketAdapter.socket,
            Duration(seconds: _clusterConfig.timeout),
            _isSeedNode(handshakeResponse.node.nodeId),
            handshakeResponse.clusterInitialized,
          );
          _missingAdditionalNodes.remove(handshakeResponse.node.nodeId);
          closedConnectionHandler.nodeId = handshakeResponse.node.nodeId;
        } else {
          _log.info('connectToNodes | remote node already present. closing socket...');
          socket.destroy();
          _log.info('connectToNodes | socket closed');
        }
      } catch (e) {
        _log.info('connectToNodes | error: $e');
        _log.info('connectToNodes | closing socket...');
        socketToClose?.destroy();
        _log.info('connectToNodes | socket closed');
      }
    }
    // initialize cluster
    if (!_hasMissingNodes()) {
      _stopConnectingToMissingNodes();
      await _initializeCluster();
    }

    _log.info('connectToNodes >');
  }

  List<ConfigNode> _missingSeedNodes() {
    return _clusterConfig.nodes
        .where((node) => node.id != _nodeConfig.node.id)
        .where((node) => !_localNode.isConnected(node.id))
        .toList();
  }

  bool _hasMissingNodes() {
    return _missingSeedNodes().isNotEmpty || _missingAdditionalNodes.isNotEmpty || !_allRequiredTagsAvailable();
  }

  bool _isSeedNode(String nodeId) {
    return _clusterConfig.nodes.map((e) => e.id).toSet().contains(nodeId);
  }

  bool _allRequiredTagsAvailable() {
    _log.info('allRequiredTagsPresent <');
    final availableTags = <String, int>{};
    for (final remoteNode in _localNode.remoteNodes()) {
      _log.info('allRequiredTagsPresent | node=${remoteNode.nodeId}, tags=${remoteNode.tags}');
      for (final tag in remoteNode.tags) {
        availableTags.putIfAbsent(tag, () => 0);
        availableTags[tag] = availableTags[tag]! + 1;
      }
    }
    _log.info('allRequiredTagsPresent | node=${_nodeConfig.node.id}, tags=${_nodeConfig.tags}');
    for (final tag in _nodeConfig.tags) {
      availableTags.putIfAbsent(tag, () => 0);
      availableTags[tag] = availableTags[tag]! + 1;
    }
    _log.info('allRequiredTagsPresent | available tags=$availableTags');
    _log.info('allRequiredTagsPresent | required tags=${_clusterConfig.tags}');

    var result = true;
    for (final requiredTag in _clusterConfig.tags.entries) {
      if (!availableTags.containsKey(requiredTag.key) || availableTags[requiredTag.key]! < requiredTag.value) {
        _log.info('allRequiredTagsPresent | missing nodes for tag ${requiredTag.key}');
        result = false;
        break;
      }
    }

    _log.info('allRequiredTagsPresent > $result');
    return result;
  }

  void _startConnectingToMissingNodes() {
    _log.info('startConnectingToMissingNodes <');
    if (_connectTimer == null && _hasMissingNodes()) {
      _log.info('startConnectingToMissingNodes | starting periodic timer');
      _connectTimer = Timer.periodic(
        Duration(seconds: 5),
        (_) => _connectToNodes(),
      );
      _log.info('startConnectingToMissingNodes | timer started');
    }
    _log.info('startConnectingToMissingNodes >');
  }

  void _stopConnectingToMissingNodes() {
    _log.info('stopConnectingToMissingNodes <');
    _connectTimer?.cancel();
    _connectTimer = null;
    _log.info('stopConnectingToMissingNodes >');
  }

  Future<void> _stopWorkers() async {
    _log.info('stopWorkers <');
    await _localNode.stopWorkers();
    _log.info('stopWorkers >');
  }

  Future<void> _startNode() async {
    _log.info('startNode <');
    _log.info('startNode | state is ${_state.name}');
    if (_state == NodeState.starting) {
      for (var workerId = 1; workerId <= _nodeConfig.workers; workerId++) {
        final receivePort = ReceivePort();
        final isolate = await Isolate.spawn<WorkerBootstrapMsg>(
          bootstrapWorker,
          WorkerBootstrapMsg(
            _nodeConfig.node.id,
            workerId,
            _clusterConfig.timeout,
            _addActorFactories,
            _serDes,
            receivePort.sendPort,
            _logLevel,
            _onLogRecord,
          ),
          debugName: '${_nodeConfig.node.id}_$workerId',
        );
        _localNode.addWorker(
            workerId, isolate, IsolateChannel.connectReceive(receivePort), Duration(seconds: _clusterConfig.timeout));
      }
      _log.info('startNode | ${_nodeConfig.workers} worker(s) started');

      final initNode = _initNode;
      if (initNode != null) {
        try {
          _log.info('startNode | calling init node callback...');
          await initNode(createCreateActor(_localNode), List.from(_nodeConfig.tags));
          _log.info('startNode | init node callback finished');
        } catch (e) {
          _log.info('startNode | returned from init node callback with error: $e');
          shutdown();
        }
      }

      _state = NodeState.started;
      _log.info('startNode | set state to ${_state.name}');
    } else {
      throw StateError('startNode() was called in state $_state, which is an error!');
    }
    _log.info('startNode >');
  }

  Future<void> _initializeCluster() async {
    _log.info('initCluster <');
    final isClusterInitialized = _localNode.isClusterInitialized;
    _log.info('initCluster | cluster is ${isClusterInitialized() ? 'already' : 'not'} initialized');
    if (!isClusterInitialized()) {
      final isLeader = _localNode.isLeader();
      _log.info('initCluster | node is ${isLeader ? '' : 'not '}leader');
      if (isLeader) {
        if (_initCluster != null) {
          _log.info('initCluster | calling init cluster callback...');
          try {
            await _initCluster?.call(createClusterContext(_localNode));
            _log.info('initCluster | returned from init cluster callback');
            _localNode.publishClusterInitialized();
            _log.info('initCluster | set cluster to initialized');
          } catch (e) {
            _log.info('initCluster | returned from init cluster callback with error: $e');
            shutdown();
          }
        } else {
          _log.info('initCluster | init cluster callback not provided');
          _localNode.publishClusterInitialized();
          _log.info('initCluster | set cluster to initialized');
        }
      }
    }
    _log.info('initCluster >');
  }
}
