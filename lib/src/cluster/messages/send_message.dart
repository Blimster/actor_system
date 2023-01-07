import 'dart:typed_data';

import 'package:actor_system/src/cluster/protocol.dart';
import 'package:actor_system/src/cluster/ser_des.dart';
import 'package:msgpack_dart_with_web/msgpack_dart_with_web.dart';

class SendMessageRequest implements PackableData {
  final Uri path;
  final Object? message;
  final Uri? sender;
  final Uri? replyTo;
  final String? correlationId;
  final SerDes serDes;

  SendMessageRequest(this.path, this.message, this.sender, this.replyTo, this.correlationId, this.serDes);

  factory SendMessageRequest.unpack(Uint8List data, SerDes serDes) {
    final deserializer = Deserializer(data);
    final String path = deserializer.decode();
    final Uint8List message = deserializer.decode();
    final String? sender = deserializer.decode();
    final String? replyTo = deserializer.decode();
    final String? correlationId = deserializer.decode();
    return SendMessageRequest(
      Uri.parse(path),
      serDes.deserialize(message),
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
    serializer.encode(serDes.serialize(message));
    serializer.encode(sender?.toString());
    serializer.encode(replyTo?.toString());
    serializer.encode(correlationId?.toString());
    return serializer.takeBytes();
  }

  @override
  String toString() => 'SendMessageRequest(path=$path, message=$message, sender=$sender, replyTo=$replyTo)';
}

class SendMessageResponse implements PackableData {
  final bool success;
  final String message;

  SendMessageResponse(this.success, this.message);

  factory SendMessageResponse.unpack(Uint8List data) {
    final deserializer = Deserializer(data);
    final bool success = deserializer.decode();
    final String message = deserializer.decode();
    return SendMessageResponse(
      success,
      message,
    );
  }

  @override
  Uint8List pack() {
    final serializer = Serializer();
    serializer.encode(success);
    serializer.encode(message);
    return serializer.takeBytes();
  }

  @override
  String toString() => 'SendMessaSendMessageResponsegeRequest(success=$success, message=$message)';
}
