import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:actor_system/src/base/socket.dart';
import 'package:actor_system/src/base/string.dart';
import 'package:actor_system/src/cluster/worker.dart';
import 'package:actor_system/src/cluster/socket_Adapter.dart';
import 'package:actor_system/src/cluster/config.dart';
import 'package:actor_system/src/cluster/messages/handshake.dart';
import 'package:logging/logging.dart';
import 'package:stream_channel/isolate_channel.dart';
import 'package:yaml/yaml.dart';

Future<Config> _readConfig({String configName = 'config'}) async {
  final yaml = await File('$configName.yaml').readAsString();
  final YamlMap config = loadYaml(yaml);

  return Config(
    (config['seedNodes'] as YamlList)
        .map((e) => ConfigNode(e['host'], e['port'], e['id']))
        .toList(),
    ConfigNode(
      config['localNode']['host'],
      config['localNode']['port'],
      config['localNode']['id'],
    ),
    config['workers'],
    config['secret'],
    config['logLevel'],
  );
}

enum NodeState {
  created,
  starting,
  started,
  stopped,
}

class NodeConnection {
  final SocketAdapter socketAdapter;

  NodeConnection(this.socketAdapter);
}

class SystemNode {
  final _log = Logger('SystemNode');
  final _nodeConnections = <String, NodeConnection>{};
  final _workerChannels = <IsolateChannel<Uint8List>>[];
  final String _configName;
  late final Config _config;
  NodeState _state = NodeState.created;
  ServerSocket? _serverSocket;
  Timer? _connectTimer;

  SystemNode(this._configName);

  NodeState get state => _state;

  Future<void> init() async {
    _log.info('init <');

    _log.info('init | state is ${_state.name}');
    if (_state != NodeState.created) {
      throw StateError('node is not in state ${NodeState.created.name}');
    }

    _state = NodeState.starting;
    _log.info('init | set state to ${_state.name}');

    // read config
    _log.info('init | loading config with name $_configName...');
    _config = await _readConfig(configName: _configName);
    _log.info('init | config loaded');
    _log.info('init | seedNodes: ${_config.seedNodes}');
    _log.info('init | localNode: ${_config.localNode}');
    _log.info('init | secret: ${'*' * _config.secret.length}');
    _log.info('init | logLevel: ${_config.logLevel}');

    // set log level
    _log.info('init | configure log level');
    Logger.root.level = _config.logLevel.toLogLevel();

    // bind server socket
    _log.info('init | binding server socket to ${_config.localNode}...');
    final serverSocket = await ServerSocket.bind(
      _config.localNode.host,
      _config.localNode.port,
    );
    _serverSocket = serverSocket;

    // wait for new connections
    serverSocket.listen(_handleNewConnection);
    _log.info('init | server socket bound and waiting for connections...');

    // periodically connect to other seed nodes
    if (_hasMissingSeedNodes()) {
      _startConnectingToMissingNodes();
    } else {
      await _startNode();
    }

    _log.info('init >');
  }

  void shutdown() {
    _log.info('shutdown <');
    _serverSocket?.close();
    _log.info('shutdown | server socket closed');
    _stopConnectingToMissingNodes();
    _log.info('shutdown | connecting to missinh nodes stopped');
    _state = NodeState.stopped;
    _log.info('shutdown | set state to ${_state.name}');
    _log.info('shutdown >');
  }

  Future<void> _handleNewConnection(Socket socket) async {
    final timeout = 3;
    _log.info('handleNewConnection < socket=${socket.address}');
    final timer = Timer(Duration(seconds: timeout),
        () => _handleTimedOutConnection(timeout, socket));
    try {
      final socketAdapter = SocketAdapter(socket);
      final message = await socketAdapter.receiveData();

      // received a message, cancel the timer
      timer.cancel();

      // check message type
      if (message.type != handshakeRequestType) {
        throw StateError(
            'invalid handshake message type. message type=${message.type}');
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
      if (_nodeConnections.containsKey(handshakeRequest.nodeId)) {
        throw StateError('node already connected');
      }

      // check same node
      if (handshakeRequest.nodeId == _config.localNode.id) {
        throw StateError('same nodeId');
      }

      // listen to socket close
      socketAdapter.onClose =
          () => _handleClosedConnection(handshakeRequest.nodeId);

      // send handshake response
      await socketAdapter.sendMessage(SocketMessage(
        handshakeResponseType,
        HandshakeResponse(_config.localNode.id).toJson(),
      ));

      // store connection
      _addConnection(handshakeRequest.nodeId, NodeConnection(socketAdapter));

      if (!_hasMissingSeedNodes()) {
        await _startNode();
      }
    } catch (e) {
      timer.cancel();
      _log.info('handleNewConnection | error: $e');
      _log.info('handleNewConnection | closing socket...');
      socket.destroy();
      _log.info('handleNewConnection | socket closed');
    }
    _log.info('handleNewConnection >');
  }

  void _handleTimedOutConnection(int timeout, Socket socket) {
    _log.info(
        'handleTimedOutConnection < timeout=$timeout, socket=${socket.addressToString()}');
    _log.info('handleTimedOutConnection | closing socket...');
    socket.destroy();
    _log.info('handleTimedOutConnection | socket closed');
    _log.info('handleTimedOutConnection >');
  }

  void _handleClosedConnection(String nodeId) {
    _log.info('handleClosedConnection < nodeId=$nodeId');
    _nodeConnections.remove(nodeId);
    if (_hasMissingSeedNodes()) {
      _startConnectingToMissingNodes();
    }
    _log.info('handleClosedConnection | connection for nodeId=$nodeId removed');
    _log.info('handleClosedConnection >');
  }

  Future<void> _connectToSeedNodes() async {
    _log.info('connectToSeedNodes <');
    final missingNodes = _config.seedNodes
        .where((node) => !_nodeConnections.containsKey(node.id))
        .where((node) => node.id != _config.localNode.id)
        .toList();
    _log.info(
        'connectToSeedNodes | missingNodes=${missingNodes.map((e) => e.id).toList()}');
    for (final node in missingNodes) {
      Socket? socketToClose;
      try {
        _log.info('connectToSeedNodes | trying to connect to node ${node.id}');

        // open socket connection
        final socket = await Socket.connect(node.host, node.port);
        final socketAdapter = SocketAdapter(socket);
        socketToClose = socket;
        _log.info('connectToSeedNodes | connection established');

        // send handshake request
        _log.info('connectToSeedNodes | sending handshake request...');
        socketAdapter.sendMessage(SocketMessage(
          handshakeRequestType,
          HandshakeRequest(
            _config.secret,
            _config.localNode.id,
          ).toJson(),
        ));

        // read response type and check it
        _log.info('connectToSeedNodes | waiting for handshake response...');
        final response = await socketAdapter.receiveData();
        if (response.type != handshakeResponseType) {
          throw StateError('invalid handshake response type');
        }

        // read handshake response and check node id
        final handshakeResponse = HandshakeResponse.fromJson(response.content);
        if (handshakeResponse.nodeId != node.id) {
          throw StateError('invalid handshake response nodeId');
        }
        _log.info('connectToSeedNodes | received handshake response');

        // remove connection on closed socket
        socketAdapter.onClose = () => _handleClosedConnection(node.id);

        // store connection
        _addConnection(node.id, NodeConnection(socketAdapter));
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

  void _addConnection(String nodeId, NodeConnection connection) {
    _log.info('addConnection < nodeId=$nodeId');
    if (_nodeConnections.containsKey(nodeId)) {
      _log.warning('addConnection | connection for already exists');
      _log.info('addConnection | closing socket...');
      connection.socketAdapter.close();
      _log.info('addConnection | socket closed');
    } else {
      _nodeConnections[nodeId] = connection;
      _log.info('addConnection | connection added');
    }
    _log.info('addConnection >');
  }

  List<ConfigNode> _missingSeedNodes() {
    return _config.seedNodes
        .where((node) => !_nodeConnections.containsKey(node.id))
        .where((node) => node.id != _config.localNode.id)
        .toList();
  }

  bool _hasMissingSeedNodes() {
    return _missingSeedNodes().isNotEmpty;
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

  Future<void> _startNode() async {
    _log.info('startNode <');
    _stopConnectingToMissingNodes();
    _log.info('startNode | state is ${_state.name}');
    if (_state != NodeState.started) {
      for (var workerId = 0; workerId < _config.workers; workerId++) {
        final receivePort = ReceivePort();
        await Isolate.spawn<WorkerBootstrapMsg>(
          bootstrapWorker,
          WorkerBootstrapMsg(
            _config.localNode.id,
            workerId,
            receivePort.sendPort,
          ),
          debugName: '${_config.localNode.id}:$workerId',
        );
        _workerChannels
            .add(IsolateChannel<Uint8List>.connectReceive(receivePort));
      }
      _log.info('startNode | ${_config.workers} worker(s) started');
      _state = NodeState.started;
      _log.info('startNode | set state to ${_state.name}');
    }
    _log.info('startNode >');
  }
}
