import 'dart:async';
import 'dart:typed_data';

import 'package:actor_system/src/cluster/messages/create_actor.dart';
import 'package:actor_system/src/cluster/messages/lookup_actor.dart';
import 'package:actor_system/src/cluster/messages/send_message.dart';
import 'package:actor_system/src/cluster/ref_proxy.dart';
import 'package:actor_system/src/cluster/ser_des.dart';
import 'package:actor_system/src/system/ref.dart';
import 'package:logging/logging.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:uuid/uuid.dart';

const createActorMessageName = 'ca';
const lookupActorMessageName = 'la';
const sendMessageMessageName = 'sm';

enum ProtocolMessageType {
  request,
  response,
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

class Protocol {
  final Logger _log;
  final Map<String, _PendingResponse> _pendingResponses = {};
  final StreamChannel<ProtocolMessage> _channel;
  final SerDes _serDes;
  final Duration _timeout;
  final Future<CreateActorResponse> Function(Uri path, int? mailboxSize, bool? useExistingActor) _handleCreateActor;
  final Future<LookupActorResponse> Function(Uri path) _handleLookupActor;
  final Future<SendMessageResponse> Function(Uri path, Object? message, Uri? sender, Uri? replyTo) _handleSendMessage;

  Protocol(
    String id,
    this._channel,
    this._serDes,
    this._timeout,
    this._handleCreateActor,
    this._handleLookupActor,
    this._handleSendMessage,
  ) : _log = Logger('actor_system.cluster.Protocol:$id') {
    _channel.stream.listen(_onMessage);
  }

  Future<ActorRef> createActor(Uri path, int? mailboxSize, bool? useExistingActor) {
    _log.fine('createActor < path=$path, mailboxSize=$mailboxSize, useExistingActor=$useExistingActor');

    final request = ProtocolMessage(
      ProtocolMessageType.request,
      createActorMessageName,
      Uuid().v4(),
      CreateActorRequest(path, mailboxSize, useExistingActor),
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

  Future<void> sendMessage(Uri path, Object? message, Uri? sender, Uri? replyTo) {
    _log.fine('sendMessage < path=$path, message=$message, sender=$sender, replyTo=$replyTo');

    final request = ProtocolMessage(
      ProtocolMessageType.request,
      sendMessageMessageName,
      Uuid().v4(),
      SendMessageRequest(path, message, sender, replyTo, _serDes),
    );

    final completer = Completer<void>();
    final timeoutTimer = Timer(_timeout, () => _handleTimeout(request.correlationId));
    _pendingResponses[request.correlationId] = _PendingResponse(completer, timeoutTimer);

    _channel.sink.add(request);

    _log.fine('sendMessage >');
    return completer.future;
  }

  Future<void> close() async {
    _log.fine('close <');
    await _channel.sink.close();
    _log.fine('close >');
  }

  void _onMessage(ProtocolMessage message) async {
    _log.fine('onMessage < message=$message');
    switch (message.type) {
      case ProtocolMessageType.request:
        switch (message.name) {
          case createActorMessageName:
            final request = message.data as CreateActorRequest;
            final response = ProtocolMessage(
              ProtocolMessageType.response,
              message.name,
              message.correlationId,
              await _handleCreateActor(request.path, request.mailboxSize, request.useExistingActor),
            );
            _channel.sink.add(response);
            break;
          case lookupActorMessageName:
            final request = message.data as LookupActorRequest;
            final response = ProtocolMessage(
              ProtocolMessageType.response,
              message.name,
              message.correlationId,
              await _handleLookupActor(request.path),
            );
            _channel.sink.add(response);
            break;
          case sendMessageMessageName:
            final request = message.data as SendMessageRequest;
            final response = ProtocolMessage(
              ProtocolMessageType.response,
              message.name,
              message.correlationId,
              await _handleSendMessage(request.path, request.message, request.sender, request.replyTo),
            );
            _channel.sink.add(response);
            break;
          default:
            throw StateError('message name ${message.name} is not supported');
        }
        break;
      case ProtocolMessageType.response:
        final pendingResponse = _pendingResponses.remove(message.correlationId);
        if (pendingResponse != null) {
          pendingResponse.timeoutTimer.cancel();
          switch (message.name) {
            case createActorMessageName:
              final response = message.data as CreateActorResponse;
              if (response.success) {
                pendingResponse.completer.complete(ActorRefProxy(Uri.parse(response.message), sendMessage));
              } else {
                pendingResponse.completer.completeError(Exception(response.message));
              }
              break;
            case lookupActorMessageName:
              final response = message.data as LookupActorResponse;
              final responsePath = response.path;
              if (responsePath != null) {
                pendingResponse.completer.complete(ActorRefProxy(responsePath, sendMessage));
              } else {
                pendingResponse.completer.complete(null);
              }
              break;
            case sendMessageMessageName:
              final response = message.data as SendMessageResponse;
              if (response.success) {
                pendingResponse.completer.complete(null);
              } else {
                pendingResponse.completer.completeError(Exception(response.message));
              }
              break;
            default:
              throw StateError('message name ${message.name} is not supported');
          }
        }
        break;
      default:
        throw StateError('message type ${message.type.name} is not supported');
    }
    _log.fine('onMessage >');
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
}
