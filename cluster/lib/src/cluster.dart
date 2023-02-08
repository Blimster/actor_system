import 'dart:async';
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
  final _uuid = Uuid().v4();
  final SerDes _serDes;
  final Config _config;
  final Level? _logLevel;
  final void Function(LogRecord)? _onLogRecord;
  late final LocalNode _localNode;
  bool _clusterInitialized = false;
  InitCluster? _initCluster;
  AddActorFactories? _addActorFactories;
  NodeState _state = NodeState.created;
  ServerSocket? _serverSocket;
  Timer? _connectTimer;

  ActorCluster(Config config, SerDes serDes, {Level? logLevel, void Function(LogRecord)? onLogRecord})
      : _config = config,
        _serDes = serDes,
        _logLevel = logLevel,
        _onLogRecord = onLogRecord;

  NodeState get state => _state;

  Future<void> init({
    InitCluster? initCluster,
    AddActorFactories? addActorFactories,
  }) async {
    _log.info('init < initCluster=$initCluster, addActorFactories=$addActorFactories');

    _log.info('init | state is ${_state.name}');
    if (_state != NodeState.created) {
      throw StateError('node is not in state ${NodeState.created.name}');
    }

    _initCluster = initCluster;
    _addActorFactories = addActorFactories;

    _state = NodeState.starting;
    _log.info('init | set state to ${_state.name}');

    // read config
    _log.info('init | configuration entries:');
    _log.info('init | - seedNodes: ${_config.seedNodes}');
    _log.info('init | - localNode: ${_config.localNode}');
    _log.info('init | - workers: ${_config.workers}');
    _log.info('init | - secret: ${'*' * _config.secret.length}');
    _log.info('init | - timeout: ${_config.timeout}');
    _log.info('init | - node uuid: $_uuid');

    // validate config
    if (_config.localNode.id == localSystem) {
      throw ArgumentError.value(
        'localNode.id',
        _config.localNode.id,
        '"$localSystem" is reserved.',
      );
    }
    final uri = Uri.tryParse('//${_config.localNode.id}:8000/');
    if (uri == null) {
      throw ArgumentError.value(
        'localNode.id',
        _config.localNode.id,
        'must be a valid host in an URI',
      );
    }

    _localNode = LocalNode(_serDes, _config.localNode.id, _uuid);

    // bind server socket
    _log.info('init | binding server socket to ${_config.localNode}...');
    final serverSocket = await ServerSocket.bind(
      _config.localNode.host,
      _config.localNode.port,
    );
    _serverSocket = serverSocket;

    // wait for new connections
    serverSocket.listen(_handleNewConnection);
    _log.info('init | server socket bound and waiting for connections');

    // periodically connect to other seed nodes
    if (_hasMissingSeedNodes()) {
      _startConnectingToMissingNodes();
    } else {
      _stopConnectingToMissingNodes();
      await _startNode();
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
      final handshakeRequest = HandshakeRequest.fromJson(message.content);
      _log.info('handleNewConnection | handshake request received');

      // check secret
      if (handshakeRequest.secret != _config.secret) {
        throw StateError('invalid handshake secret');
      }
      _log.info('handleNewConnection | secret is valid');
      _log.info('handleNewConnection | nodeId=${handshakeRequest.nodeId}');

      // check if node is already connected
      if (_localNode.isConnected(handshakeRequest.nodeId)) {
        throw StateError('node already connected');
      }

      // check same node
      if (handshakeRequest.nodeId == _config.localNode.id) {
        throw StateError('same node id');
      }

      // check for seed node
      if (!_missingSeedNodes().map((e) => e.id).contains(handshakeRequest.nodeId)) {
        throw StateError('not a seed node');
      }

      // send handshake response
      await socketAdapter.sendMessage(SocketMessage(
        handshakeResponseType,
        HandshakeResponse(
          handshakeRequest.correlationId,
          _config.localNode.id,
          _uuid,
          _config.workers,
          _clusterInitialized,
        ).toJson(),
      ));

      if (!_localNode.isConnected(handshakeRequest.nodeId)) {
        // store connection
        _localNode.addRemoteNode(
          handshakeRequest.nodeId,
          handshakeRequest.uuid,
          handshakeRequest.workers,
          socketAdapter.streamReader,
          socketAdapter.socket,
          Duration(seconds: _config.timeout),
          handshakeRequest.clusterInitialized,
          _handleClusterInitialized,
        );

        // handle closed connection
        closedConnectionHandler.nodeId = handshakeRequest.nodeId;
      } else {
        _log.info('handleNewConnection | remote node already present. closing socket...');
        socket.destroy();
        _log.info('handleNewConnection | socket closed');
      }

      if (!_hasMissingSeedNodes()) {
        _stopConnectingToMissingNodes();
        await _startNode();
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
    if (_hasMissingSeedNodes()) {
      _startConnectingToMissingNodes();
    }
    _log.info('handleClosedConnection >');
  }

  Future<void> _connectToSeedNodes() async {
    _log.info('connectToSeedNodes <');
    final missingSeedNodes = _missingSeedNodes();
    _log.info('connectToSeedNodes | missingSeedNodes=${missingSeedNodes.map((e) => e.id).toList()}');
    for (final node in missingSeedNodes) {
      Socket? socketToClose;
      try {
        _log.info('connectToSeedNodes | trying to connect to node ${node.id}');

        // open socket connection
        final closedConnectionHandler = ClosedConnectionHandler(_handleClosedConnection);
        final socket = await Socket.connect(node.host, node.port);
        final socketAdapter = SocketAdapter(socket);
        socketAdapter.bind(onDone: closedConnectionHandler);
        socketToClose = socket;
        _log.info('connectToSeedNodes | connection established');

        // send handshake request
        _log.info('connectToSeedNodes | sending handshake request...');
        final correlationId = Uuid().v4();
        socketAdapter.sendMessage(SocketMessage(
          handshakeRequestType,
          HandshakeRequest(
            correlationId,
            _config.secret,
            _config.localNode.id,
            _uuid,
            _config.workers,
            _clusterInitialized,
          ).toJson(),
        ));

        // read response type and check it
        _log.info('connectToSeedNodes | waiting for handshake response...');
        final response = await socketAdapter.receiveData();
        if (response.type != handshakeResponseType) {
          throw StateError('invalid handshake response type');
        }

        // read handshake response
        final handshakeResponse = HandshakeResponse.fromJson(response.content);
        _log.info('connectToSeedNodes | received handshake response');

        // check correlation id
        if (handshakeResponse.correlationId != correlationId) {
          throw StateError('invalid handshake response correlation id (${handshakeResponse.correlationId})');
        }

        // check node id
        if (handshakeResponse.nodeId != node.id) {
          throw StateError('invalid handshake response node id (${handshakeResponse.nodeId})');
        }

        // check uuid
        if (handshakeResponse.uuid == _uuid) {
          throw StateError('remote node has same uuid');
        }

        // store connection
        if (!_localNode.isConnected(handshakeResponse.nodeId)) {
          _localNode.addRemoteNode(
            handshakeResponse.nodeId,
            handshakeResponse.uuid,
            handshakeResponse.workers,
            socketAdapter.streamReader,
            socketAdapter.socket,
            Duration(seconds: _config.timeout),
            handshakeResponse.clusterInitialized,
            _handleClusterInitialized,
          );
          closedConnectionHandler.nodeId = handshakeResponse.nodeId;
        } else {
          _log.info('connectToSeedNodes | remote node already present. closing socket...');
          socket.destroy();
          _log.info('connectToSeedNodes | socket closed');
        }
      } catch (e) {
        _log.info('connectToSeedNodes | error: $e');
        _log.info('connectToSeedNodes | closing socket...');
        socketToClose?.destroy();
        _log.info('connectToSeedNodes | socket closed');
      }
    }
    // start node
    if (!_hasMissingSeedNodes()) {
      _stopConnectingToMissingNodes();
      await _startNode();
      await _initializeCluster();
    }

    _log.info('connectToSeedNodes >');
  }

  List<ConfigNode> _missingSeedNodes() {
    return _config.seedNodes
        .where((node) => node.id != _config.localNode.id)
        .where((node) => !_localNode.isConnected(node.id))
        .toList();
  }

  bool _hasMissingSeedNodes() {
    return _missingSeedNodes().isNotEmpty;
  }

  bool _isLeader() {
    final remoteUuids = _localNode.remoteUuids();
    if (remoteUuids.isEmpty) {
      return true;
    }
    final smallestRemoteUuid = remoteUuids.first;
    return _uuid.compareTo(smallestRemoteUuid) < 0;
  }

  bool _isClusterInitialized() {
    for (final isInitialized in _localNode.clusterInitializationState().values) {
      if (isInitialized == true) {
        return true;
      }
    }
    return _clusterInitialized;
  }

  void _handleClusterInitialized(String nodeId) {
    _log.info('handleClusterInitialized <');
    _log.info('handleClusterInitialized | cluster initialized by node $nodeId');
    _clusterInitialized = true;
    _log.info('handleClusterInitialized | set cluster to initialized');
    _log.info('handleClusterInitialized >');
  }

  void _startConnectingToMissingNodes() {
    _log.info('startConnectingToMissingNodes <');
    if (_connectTimer == null && _hasMissingSeedNodes()) {
      _log.info('startConnectingToMissingNodes | starting periodic timer');
      _connectTimer = Timer.periodic(
        Duration(seconds: 5),
        (_) => _connectToSeedNodes(),
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
      for (var workerId = 1; workerId <= _config.workers; workerId++) {
        final receivePort = ReceivePort();
        final isolate = await Isolate.spawn<WorkerBootstrapMsg>(
          bootstrapWorker,
          WorkerBootstrapMsg(
            _config.localNode.id,
            workerId,
            _config.timeout,
            _addActorFactories,
            _serDes,
            receivePort.sendPort,
            _logLevel,
            _onLogRecord,
          ),
          debugName: '${_config.localNode.id}_$workerId',
        );
        _localNode.addWorker(
            workerId, isolate, IsolateChannel.connectReceive(receivePort), Duration(seconds: _config.timeout));
      }
      _log.info('startNode | ${_config.workers} worker(s) started');
      _state = NodeState.started;
      _log.info('startNode | set state to ${_state.name}');
    } else if (_state == NodeState.started) {
      _log.info('startNode | skipped starting workers');
    } else {
      throw StateError('startNode() was called in state $_state, which is an error!');
    }
    _log.info('startNode >');
  }

  Future<void> _initializeCluster() async {
    _log.info('initCluster <');
    final isClusterInitialized = _isClusterInitialized();
    _log.info('initCluster | cluster is ${isClusterInitialized ? 'already' : 'not'} initialized');
    if (!isClusterInitialized) {
      final isLeader = _isLeader();
      _log.info('initCluster | node is ${isLeader ? '' : 'not '}leader');
      if (isLeader) {
        if (_initCluster != null) {
          _log.info('initCluster | calling init cluster callback...');
          try {
            await _initCluster?.call(createClusterContext(_localNode));
            _log.info('initCluster | returned from init cluster callback');
            _clusterInitialized = true;
            _localNode.publishClusterInitialized(_localNode.nodeId);
            _log.info('initCluster | set cluster to initialized');
          } catch (e) {
            _log.info('initCluster | returned from init cluster callback with error: $e');
            shutdown();
          }
        } else {
          _log.info('initCluster | init cluster callback not provided');
          _clusterInitialized = true;
          _log.info('initCluster | set cluster to initialized');
        }
      }
    }
    _log.info('initCluster >');
  }
}
