import 'dart:typed_data';

import 'package:actor_system/src/cluster/protocol.dart';
import 'package:actor_system/src/cluster/ser_des.dart';
import 'package:msgpack_dart_with_web/msgpack_dart_with_web.dart';

class SendMessageRequest implements PackableData {
  final Uri path;
  final Object? message;
  final Uri? replyTo;
  final SerDes serDes;

  SendMessageRequest(this.path, this.message, this.replyTo, this.serDes);

  factory SendMessageRequest.unpack(Uint8List data, SerDes serDes) {
    final deserializer = Deserializer(data);
    final String path = deserializer.decode();
    final Uint8List message = deserializer.decode();
    final String? replyTo = deserializer.decode();
    return SendMessageRequest(
      Uri.parse(path),
      serDes.deserialize(message),
      replyTo != null ? Uri.parse(replyTo) : null,
      serDes,
    );
  }

  @override
  Uint8List pack() {
    final serializer = Serializer();
    serializer.encode(path.toString());
    serializer.encode(serDes.serialize(message));
    serializer.encode(replyTo?.toString());
    return serializer.takeBytes();
  }

  @override
  String toString() => 'SendMessageRequest(path=$path, message=$message, replyTo=$replyTo)';
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
