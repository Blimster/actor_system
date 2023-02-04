import 'dart:typed_data';

import 'package:actor_cluster/src/protocol.dart';
import 'package:msgpack_dart/msgpack_dart.dart';

class CreateActorRequest implements PackableData {
  final Uri path;
  final int? mailboxSize;

  CreateActorRequest(this.path, this.mailboxSize);

  factory CreateActorRequest.unpack(Uint8List data) {
    final deserializer = Deserializer(data);
    return CreateActorRequest(
      Uri.parse(deserializer.decode()),
      deserializer.decode(),
    );
  }

  @override
  Uint8List pack() {
    final serializer = Serializer();
    serializer.encode(path.toString());
    serializer.encode(mailboxSize);
    return serializer.takeBytes();
  }

  @override
  String toString() => 'CreateActorRequest(path=$path, mailboxSize=$mailboxSize)';
}

class CreateActorResponse implements PackableData {
  final bool success;
  final String message;

  CreateActorResponse(this.success, this.message);

  factory CreateActorResponse.unpack(Uint8List data) {
    final deserializer = Deserializer(data);
    return CreateActorResponse(
      deserializer.decode(),
      deserializer.decode(),
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
  String toString() => 'CreateActorResponse(success=$success, message=$message)';
}
