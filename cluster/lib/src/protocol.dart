import 'dart:async';
import 'dart:typed_data';

import 'package:actor_cluster/src/messages/cluster_initialized.dart';
import 'package:actor_cluster/src/messages/create_actor.dart';
import 'package:actor_cluster/src/messages/lookup_actor.dart';
import 'package:actor_cluster/src/messages/lookup_actors.dart';
import 'package:actor_cluster/src/messages/send_message.dart';
import 'package:actor_cluster/src/ref_proxy.dart';
import 'package:actor_cluster/src/ser_des.dart';
import 'package:actor_system/actor_system.dart';
import 'package:logging/logging.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:uuid/uuid.dart';

const clusterInitializedMessageName = 'ci';
const createActorMessageName = 'ca';
const lookupActorMessageName = 'la';
const lookupActorsMessageName = 'las';
const sendMessageMessageName = 'sm';

enum ProtocolMessageType {
  request,
  response,
  oneWay,
}

abstract class PackableData {
  Uint8List pack();
}

class ProtocolMessage {
  final ProtocolMessageType type;
  final String name;
  final String correlationId;
  final PackableData data;

  ProtocolMessage(this.type, this.name, this.correlationId, this.data);

  @override
  String toString() {
    return 'ProtocolMessage(type=$type, name=$name, correlationId=$correlationId, data=$data)';
  }
}

class _PendingResponse {
  final Completer completer;
  final Timer timeoutTimer;

  _PendingResponse(this.completer, this.timeoutTimer);
}

abstract class BaseProtocol {
  final Logger _log;
  final Map<String, void Function(ProtocolMessage)> _messageHandlers = {};
  final Map<String, _PendingResponse> _pendingResponses = {};
  final StreamChannel<ProtocolMessage> _channel;
  final SerDes _serDes;
  final Duration _timeout;

  BaseProtocol(
    String id,
    this._channel,
    this._serDes,
    this._timeout,
  ) : _log = Logger('actor_system.cluster.Protocol:$id') {
    {
      final sub = _channel.stream.listen(_onMessage);
      sub.onError((err) {
        sub.cancel();
      });
    }
  }

  void addMessageHandler(ProtocolMessageType type, String name, void Function(ProtocolMessage) handler) {
    _messageHandlers['${type.name}@$name'] = handler;
  }

  Future<void> close() async {
    _log.fine('close <');
    await _channel.sink.close();
    _log.fine('close >');
  }

  void _handleTimeout(String correlationId) {
    final pendingResponse = _pendingResponses.remove(correlationId);
    if (pendingResponse != null && !pendingResponse.completer.isCompleted) {
      pendingResponse.completer.completeError(TimeoutException(
        'timeout waiting for response',
        _timeout,
      ));
    }
  }

  Future<void> _onMessage(ProtocolMessage message) async {
    _log.fine('_onMessage < message=$message');

    final handler = _messageHandlers['${message.type.name}@${message.name}'];
    if (handler != null) {
      handler(message);
    } else {
      throw StateError('no handler for message with type ${message.type.name} and name ${message.name} registered');
    }

    _log.fine('_onMessage >');
  }
}

class ActorProtocol extends BaseProtocol {
  final Future<CreateActorResponse> Function(Uri path, int? mailboxSize) _handleCreateActor;
  final Future<LookupActorResponse> Function(Uri path) _handleLookupActor;
  final Future<LookupActorsResponse> Function(Uri path) _handleLookupActors;
  final Future<SendMessageResponse> Function(
      Uri path, Object? message, Uri? sender, Uri? replyTo, String? correlationId) _handleSendMessage;

  ActorProtocol(
    super.id,
    super.channel,
    super.serDes,
    super.timeout,
    this._handleCreateActor,
    this._handleLookupActor,
    this._handleLookupActors,
    this._handleSendMessage,
  ) {
    addMessageHandler(ProtocolMessageType.request, createActorMessageName, _handleCreateActorRequest);
    addMessageHandler(ProtocolMessageType.response, createActorMessageName, _handleCreateActorResponse);
    addMessageHandler(ProtocolMessageType.request, lookupActorMessageName, _handleLookupActorRequest);
    addMessageHandler(ProtocolMessageType.response, lookupActorMessageName, _handleLookupActorResponse);
    addMessageHandler(ProtocolMessageType.request, lookupActorsMessageName, _handleLookupActorsRequest);
    addMessageHandler(ProtocolMessageType.response, lookupActorsMessageName, _handleLookupActorsResponse);
    addMessageHandler(ProtocolMessageType.request, sendMessageMessageName, _handleSendMessageRequest);
    addMessageHandler(ProtocolMessageType.response, sendMessageMessageName, _handleSendMessageResponse);
  }

  Future<ActorRef> createActor(Uri path, int? mailboxSize) {
    _log.fine('createActor < path=$path, mailboxSize=$mailboxSize');

    final request = ProtocolMessage(
      ProtocolMessageType.request,
      createActorMessageName,
      Uuid().v4(),
      CreateActorRequest(path, mailboxSize),
    );

    final completer = Completer<ActorRef>();
    final timeoutTimer = Timer(_timeout, () => _handleTimeout(request.correlationId));
    _pendingResponses[request.correlationId] = _PendingResponse(completer, timeoutTimer);

    _channel.sink.add(request);

    _log.fine('createActor >');
    return completer.future;
  }

  Future<ActorRef?> lookupActor(Uri path) {
    _log.fine('lookupActor < path=$path');

    final request = ProtocolMessage(
      ProtocolMessageType.request,
      lookupActorMessageName,
      Uuid().v4(),
      LookupActorRequest(path),
    );

    final completer = Completer<ActorRef?>();
    final timeoutTimer = Timer(_timeout, () => _handleTimeout(request.correlationId));
    _pendingResponses[request.correlationId] = _PendingResponse(completer, timeoutTimer);

    _channel.sink.add(request);

    _log.fine('lookupActor >');
    return completer.future;
  }

  Future<List<ActorRef>> lookupActors(Uri path) {
    _log.fine('lookupActors < path=$path');

    final request = ProtocolMessage(
      ProtocolMessageType.request,
      lookupActorsMessageName,
      Uuid().v4(),
      LookupActorsRequest(path),
    );

    final completer = Completer<List<ActorRef>>();
    final timeoutTimer = Timer(_timeout, () => _handleTimeout(request.correlationId));
    _pendingResponses[request.correlationId] = _PendingResponse(completer, timeoutTimer);

    _channel.sink.add(request);

    _log.fine('lookupActors >');
    return completer.future;
  }

  Future<void> sendMessage(Uri path, Object? message, Uri? sender, Uri? replyTo, String? correlationId) {
    _log.fine(
        'sendMessage < path=$path, message=$message, sender=$sender, replyTo=$replyTo, correlationId=$correlationId');

    final request = ProtocolMessage(
      ProtocolMessageType.request,
      sendMessageMessageName,
      Uuid().v4(),
      SendMessageRequest(
        path,
        messageType(message),
        message,
        sender,
        replyTo,
        correlationId,
        _serDes,
      ),
    );

    final completer = Completer<void>();
    final timeoutTimer = Timer(_timeout, () => _handleTimeout(request.correlationId));
    _pendingResponses[request.correlationId] = _PendingResponse(completer, timeoutTimer);

    _channel.sink.add(request);

    _log.fine('sendMessage >');
    return completer.future;
  }

  Future<void> _handleCreateActorRequest(ProtocolMessage message) async {
    _log.fine('_handleCreateActorRequest < message=$message');
    final request = message.data as CreateActorRequest;
    final response = ProtocolMessage(
      ProtocolMessageType.response,
      message.name,
      message.correlationId,
      await _handleCreateActor(request.path, request.mailboxSize),
    );
    _channel.sink.add(response);
    _log.fine('_handleCreateActorRequest >');
  }

  Future<void> _handleCreateActorResponse(ProtocolMessage message) async {
    _log.fine('_handleCreateActorResponse < message=$message');
    final pendingResponse = _pendingResponses.remove(message.correlationId);
    if (pendingResponse != null) {
      pendingResponse.timeoutTimer.cancel();
      final response = message.data as CreateActorResponse;
      if (response.success) {
        pendingResponse.completer.complete(ActorRefProxy(Uri.parse(response.message), sendMessage));
      } else {
        pendingResponse.completer.completeError(Exception(response.message));
      }
    }
    _log.fine('_handleCreateActorResponse >');
  }

  Future<void> _handleLookupActorRequest(ProtocolMessage message) async {
    _log.fine('_handleLookupActorRequest < message=$message');
    final request = message.data as LookupActorRequest;
    final response = ProtocolMessage(
      ProtocolMessageType.response,
      message.name,
      message.correlationId,
      await _handleLookupActor(request.path),
    );
    _channel.sink.add(response);
    _log.fine('_handleLookupActorRequest >');
  }

  Future<void> _handleLookupActorResponse(ProtocolMessage message) async {
    _log.fine('_handleLookupActorResponse < message=$message');
    final pendingResponse = _pendingResponses.remove(message.correlationId);
    if (pendingResponse != null) {
      pendingResponse.timeoutTimer.cancel();
      final response = message.data as LookupActorResponse;
      final responsePath = response.path;
      if (responsePath != null) {
        pendingResponse.completer.complete(ActorRefProxy(responsePath, sendMessage));
      } else {
        pendingResponse.completer.complete(null);
      }
    }
    _log.fine('_handleLookupActorResponse >');
  }

  Future<void> _handleLookupActorsRequest(ProtocolMessage message) async {
    _log.fine('_handleLookupActorsRequest < message=$message');
    final request = message.data as LookupActorsRequest;
    final response = ProtocolMessage(
      ProtocolMessageType.response,
      message.name,
      message.correlationId,
      await _handleLookupActors(request.path),
    );
    _channel.sink.add(response);
    _log.fine('_handleLookupActorsRequest >');
  }

  Future<void> _handleLookupActorsResponse(ProtocolMessage message) async {
    _log.fine('_handleLookupActorsResponse < message=$message');
    final pendingResponse = _pendingResponses.remove(message.correlationId);
    if (pendingResponse != null) {
      pendingResponse.timeoutTimer.cancel();
      final response = message.data as LookupActorsResponse;
      final result = <ActorRef>[];
      for (final responsePath in response.paths) {
        result.add(ActorRefProxy(responsePath, sendMessage));
      }
      pendingResponse.completer.complete(result);
    }
    _log.fine('_handleLookupActorsResponse >');
  }

  Future<void> _handleSendMessageRequest(ProtocolMessage message) async {
    _log.fine('_handleSendMessageRequest < message=$message');
    final request = message.data as SendMessageRequest;
    final response = ProtocolMessage(
      ProtocolMessageType.response,
      message.name,
      message.correlationId,
      await _handleSendMessage(
        request.path,
        request.message,
        request.sender,
        request.replyTo,
        request.correlationId,
      ),
    );
    _channel.sink.add(response);
    _log.fine('_handleSendMessageRequest >');
  }

  Future<void> _handleSendMessageResponse(ProtocolMessage message) async {
    _log.fine('_handleSendMessageResponse < message=$message');
    final pendingResponse = _pendingResponses.remove(message.correlationId);
    if (pendingResponse != null) {
      pendingResponse.timeoutTimer.cancel();
      final response = message.data as SendMessageResponse;
      switch (response.result) {
        case SendMessageResult.success:
          pendingResponse.completer.complete(null);
          break;
        case SendMessageResult.mailboxFull:
          pendingResponse.completer.complete(MailboxFull());
          break;
        case SendMessageResult.actorStopped:
          pendingResponse.completer.complete(ActorStopped());
          break;
        case SendMessageResult.messageNotDelivered:
        default:
          pendingResponse.completer.completeError(MessageNotDelivered(response.message));
          break;
      }
    }
    _log.fine('_handleSendMessageResponse >');
  }
}

class ClusterProtocol extends ActorProtocol {
  final void Function(String nodeId) _handleClusterInitialized;

  ClusterProtocol(
    super.id,
    super.channel,
    super.serDes,
    super.timeout,
    super.handleCreateActor,
    super.handleLookupActor,
    super.handleLookupActors,
    super.handleSendMessage,
    this._handleClusterInitialized,
  ) {
    addMessageHandler(ProtocolMessageType.oneWay, clusterInitializedMessageName, _handleClusterInitializedMessage);
  }

  void publishClusterInitialized(String nodeId) async {
    _channel.sink.add(ProtocolMessage(
      ProtocolMessageType.oneWay,
      clusterInitializedMessageName,
      '',
      ClusterInitialized(nodeId),
    ));
  }

  void _handleClusterInitializedMessage(ProtocolMessage message) {
    _log.fine('_handleClusterInitializedMessage < message=$message');
    final data = message.data as ClusterInitialized;
    _handleClusterInitialized(data.nodeId);
    _log.fine('_handleClusterInitializedMessage >');
  }
}
