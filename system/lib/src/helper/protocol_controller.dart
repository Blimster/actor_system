import 'dart:async';

import 'package:actor_system/actor_system.dart';
import 'package:uuid/uuid.dart';

final _uuid = Uuid();

/// A function to execute the initial step of a protocol. Usually, a message is sent to another actor. It is important
/// to pass the correlationId to the message so that the response can be correlated to the initial message.
typedef ProtocolInit = FutureOr<void> Function(ActorContext ctx, String correlationId);

/// A function to execute the next step of a protocol. The function should return `true` if the protocol is complete.
typedef ProtocolOnMessage<M> = FutureOr<bool> Function(ActorContext ctx, M msg);

/// A protocol is a sequence of steps.
class Protocol {
  ProtocolInit? _init;
  final _onMessage = <Type, dynamic>{};

  Protocol._();
}

/// Protocol builder to build the init step of the protocol.
class ProtocolBuilderInit {
  final _protocol = Protocol._();

  /// Call this method to build the initial step of the protocol. Continue to call methods on the returned
  /// `ProtocolBuilderMessage` object.
  ProtocolBuilderMessage init(ProtocolInit init) {
    _protocol._init = init;
    return ProtocolBuilderMessage._(_protocol);
  }
}

/// Protocol builder to build the next steps of the protocol.
class ProtocolBuilderMessage {
  final Protocol _protocol;

  ProtocolBuilderMessage._(this._protocol);

  /// Call this method to build the next step of the protocol. Continue to call methods on the returned object.
  ProtocolBuilderMessage onMessage<M>(ProtocolOnMessage<M> onMessage) {
    if (_protocol._onMessage.containsKey(M)) {
      throw Exception('Message type already handled');
    }
    _protocol._onMessage[M] = onMessage;
    return this;
  }

  Protocol build() {
    return _protocol;
  }
}

/// A controller to run protocols. It helps you to handle a sequence of messages that are part of a protocol.
///
/// Register the controller to the actor builder to process incoming message on a protocol. Use the `runProtocol` method
/// to create a new instance of a protocol and run it.
///
/// In the init step it is important to pass the correlationId to the message so that the response can be correlated to.
///
/// Example:
/// ```dart
/// final controller = ProtocolController();
///
/// controller.runProtocol(ctx, (builder) {
///   // hold some protocol state here
///   return builder //
///     .init((ctx, correlationId) {
///       // first step of the protocol (e.g. send a request to another actor)
///     })
///     .onMessage<String>((ctx, msg) {
///       // handle incoming messages for the protocol (e.g. response from another actor)
///     })
///     .build();
/// });
///
/// final actor = ActorBuilder().withProtocolController(controller).orSkip();
/// ```
class ProtocolController {
  final _pendingProtocols = <String, Protocol>{};

  // Used by the actor builder to check if the protocol controller should handle the message.
  bool predicate(ActorContext ctx, Object? msg) {
    final correlationId = ctx.correlationId;
    if (correlationId == null) {
      return false;
    }
    return _pendingProtocols.containsKey(correlationId);
  }

  // Used by the actor builder to handle the message for the protocol.
  Future<void> actor(ActorContext ctx, Object? msg) async {
    final correlationId = ctx.correlationId;
    final protocol = _pendingProtocols[correlationId];
    if (protocol == null) {
      return;
    }
    final onMessage = protocol._onMessage[msg.runtimeType];
    if (onMessage == null) {
      throw StateError('Unexpected message: correlationId=$correlationId, type=${msg.runtimeType}');
    }
    final result = await onMessage(ctx, msg);
    if (result == true) {
      _pendingProtocols.remove(correlationId);
    }
  }

  /// Create a new instance of a protocol and run it.
  void runProtocol(
    ActorContext ctx,
    Protocol Function(ProtocolBuilderInit builder) protocolBuilder,
  ) async {
    final uuid = _uuid.v4();
    final builder = ProtocolBuilderInit();
    final protocol = protocolBuilder(builder);
    _pendingProtocols[uuid] = protocol;
    await protocol._init!(ctx, uuid);
  }
}
