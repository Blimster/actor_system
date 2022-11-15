import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:actor_system/actor_system.dart';
import 'package:actor_system/src/base/socket.dart';
import 'package:actor_system/src/base/string.dart';
import 'package:actor_system/src/cluster/config.dart';
import 'package:actor_system/src/cluster/context.dart';
import 'package:actor_system/src/cluster/messages/handshake.dart';
import 'package:actor_system/src/cluster/node.dart';
import 'package:actor_system/src/cluster/ser_des.dart';
import 'package:actor_system/src/cluster/socket_adapter.dart';
import 'package:actor_system/src/cluster/worker.dart';
import 'package:logging/logging.dart';
import 'package:stream_channel/isolate_channel.dart';
import 'package:uuid/uuid.dart';

/// Called after the cluster is initialized. This callback is called on every
/// node as the very last action in [ActorCluster.init]. Use the parameter
/// [isLeader] to execution init actions on only a single node (the leader
/// node).
typedef AfterClusterInit = FutureOr<void> Function(
  ClusterContext context,
  bool isLeader,
);

/// Called to preprare the actor system on every worker of a node. Use this
/// callback to register actor factories.
typedef PrepareNodeSystem = FutureOr<void> Function(
    void Function(Pattern pattern, ActorFactory factory) registerFactory);

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
  final _log = Logger('ActorClusterNode');
  final _uuid = Uuid().v4();
  final String _configName;
  final SerDes _serDes;
  late final Config _config;
  late final LocalNode _localNode;
  AfterClusterInit? _afterClusterInit;
  PrepareNodeSystem? _prepareNodeSystem;
  NodeState _state = NodeState.created;
  ServerSocket? _serverSocket;
  Timer? _connectTimer;

  ActorCluster(this._configName, this._serDes);

  NodeState get state => _state;

  Future<void> init({
    AfterClusterInit? afterClusterInit,
    PrepareNodeSystem? prepareNodeSystem,
  }) async {
    _log.info('init < afterInit=$afterClusterInit');

    _log.info('init | state is ${_state.name}');
    if (_state != NodeState.created) {
      throw StateError('node is not in state ${NodeState.created.name}');
    }

    _afterClusterInit = afterClusterInit;
    _prepareNodeSystem = prepareNodeSystem;

    _state = NodeState.starting;
    _log.info('init | set state to ${_state.name}');

    // read config
    _log.info('init | loading config with name $_configName...');
    _config = await readConfig(configName: _configName);
    _log.info('init | config loaded');

    _log.info('init | seedNodes: ${_config.seedNodes}');
    _log.info('init | localNode: ${_config.localNode}');
    _log.info('init | workers: ${_config.workers}');
    _log.info('init | secret: ${'*' * _config.secret.length}');
    _log.info('init | logLevel: ${_config.logLevel}');
    _log.info('init | timeout: ${_config.timeout}');
    _log.info('init | node uuid: ${_uuid}');

    // set log level
    _log.info('init | configure log level');
    Logger.root.level = _config.logLevel.toLogLevel();

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
      await _startNode();
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
        );

        // handle closed connection
        closedConnectionHandler.nodeId = handshakeRequest.nodeId;
      } else {
        _log.info('handleNewConnection | remote node already present. closing socket...');
        socket.destroy();
        _log.info('handleNewConnection | socket closed');
      }

      if (!_hasMissingSeedNodes()) {
        await _startNode();
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
      await _startNode();
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

  void _startConnectingToMissingNodes() {
    if (_connectTimer == null && _hasMissingSeedNodes()) {
      _connectTimer = Timer.periodic(
        Duration(seconds: 5),
        (_) => _connectToSeedNodes(),
      );
    }
  }

  void _stopConnectingToMissingNodes() {
    _connectTimer?.cancel();
    _connectTimer = null;
  }

  Future<void> _stopWorkers() async {
    _log.info('stopWorkers <');
    await _localNode.stopWorkers();
    _log.info('stopWorkers >');
  }

  Future<void> _startNode() async {
    _log.info('startNode <');
    _stopConnectingToMissingNodes();
    _log.info('startNode | state is ${_state.name}');
    if (_state != NodeState.started) {
      for (var workerId = 1; workerId <= _config.workers; workerId++) {
        final receivePort = ReceivePort();
        final isolate = await Isolate.spawn<WorkerBootstrapMsg>(
          bootstrapWorker,
          WorkerBootstrapMsg(
            _config.localNode.id,
            workerId,
            _config.logLevel.toLogLevel(),
            _config.timeout,
            _prepareNodeSystem,
            _serDes,
            receivePort.sendPort,
          ),
          debugName: '${_config.localNode.id}_$workerId',
        );
        _localNode.addWorker(
            workerId, isolate, IsolateChannel.connectReceive(receivePort), Duration(seconds: _config.timeout));
      }
      _log.info('startNode | ${_config.workers} worker(s) started');

      final isLeader = _isLeader();
      _log.info('startNode | node is ${isLeader ? '' : 'not '}leader');
      if (_afterClusterInit != null) {
        _log.info('startNode | calling afterInit callback...');
        try {
          await _afterClusterInit?.call(createClusterContext(_localNode), isLeader);
          _log.info('startNode | returned from afterInit callback');
          _state = NodeState.started;
          _log.info('startNode | set state to ${_state.name}');
        } catch (e) {
          _log.info('startNode | returned from afterInit callback with error: $e');
          shutdown();
        }
      }
    }
    _log.info('startNode >');
  }
}
