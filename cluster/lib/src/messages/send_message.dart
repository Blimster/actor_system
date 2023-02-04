import 'dart:typed_data';

import 'package:actor_cluster/src/protocol.dart';
import 'package:actor_cluster/src/ser_des.dart';
import 'package:actor_system/actor_system.dart';
import 'package:msgpack_dart/msgpack_dart.dart';

enum MessageType {
  payload,
  init,
  shutdown,
}

MessageType messageType(Object? message) {
  if (message == initMsg) {
    return MessageType.init;
  } else if (message == shutdownMsg) {
    return MessageType.shutdown;
  }
  return MessageType.payload;
}

class SendMessageRequest implements PackableData {
  final Uri path;
  final MessageType messageType;
  final Object? message;
  final Uri? sender;
  final Uri? replyTo;
  final String? correlationId;
  final SerDes serDes;

  SendMessageRequest(
    this.path,
    this.messageType,
    this.message,
    this.sender,
    this.replyTo,
    this.correlationId,
    this.serDes,
  );

  factory SendMessageRequest.unpack(Uint8List data, SerDes serDes) {
    final deserializer = Deserializer(data);
    final String path = deserializer.decode();
    final MessageType messageType = MessageType.values.byName(deserializer.decode());
    final Uint8List? message = deserializer.decode();
    final String? sender = deserializer.decode();
    final String? replyTo = deserializer.decode();
    final String? correlationId = deserializer.decode();

    return SendMessageRequest(
      Uri.parse(path),
      messageType,
      messageType == MessageType.payload
          ? serDes.deserialize(message!)
          : messageType == MessageType.init
              ? initMsg
              : shutdownMsg,
      sender != null ? Uri.parse(sender) : null,
      replyTo != null ? Uri.parse(replyTo) : null,
      correlationId,
      serDes,
    );
  }

  @override
  Uint8List pack() {
    final serializer = Serializer();
    serializer.encode(path.toString());
    serializer.encode(messageType.name);
    switch (messageType) {
      case MessageType.payload:
        serializer.encode(serDes.serialize(message));
        break;
      default:
        serializer.encode(null);
        break;
    }
    serializer.encode(sender?.toString());
    serializer.encode(replyTo?.toString());
    serializer.encode(correlationId?.toString());
    return serializer.takeBytes();
  }

  @override
  String toString() => 'SendMessageRequest(path=$path, message=$message, sender=$sender, replyTo=$replyTo)';
}

enum SendMessageResult {
  success,
  actorStopped,
  mailboxFull,
  messageNotDelivered,
}

class SendMessageResponse implements PackableData {
  final SendMessageResult result;
  final String message;

  SendMessageResponse(this.result, this.message);

  factory SendMessageResponse.unpack(Uint8List data) {
    final deserializer = Deserializer(data);
    final String result = deserializer.decode();
    final String message = deserializer.decode();
    return SendMessageResponse(
      SendMessageResult.values.byName(result),
      message,
    );
  }

  @override
  Uint8List pack() {
    final serializer = Serializer();
    serializer.encode(result.name);
    serializer.encode(message);
    return serializer.takeBytes();
  }

  @override
  String toString() => 'SendMessaSendMessageResponsegeRequest(result=$result, message=$message)';
}
