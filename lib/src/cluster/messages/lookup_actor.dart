import 'dart:typed_data';

import 'package:actor_system/src/cluster/protocol.dart';
import 'package:msgpack_dart/msgpack_dart.dart';

class LookupActorRequest implements PackableData {
  final Uri path;

  LookupActorRequest(this.path);

  factory LookupActorRequest.unpack(Uint8List data) {
    final deserializer = Deserializer(data);
    return LookupActorRequest(
      Uri.parse(deserializer.decode()),
    );
  }

  @override
  Uint8List pack() {
    final serializer = Serializer();
    serializer.encode(path.toString());
    return serializer.takeBytes();
  }

  @override
  String toString() => 'LookupActorRequest(path=$path)';
}

class LookupActorResponse implements PackableData {
  final Uri? path;

  LookupActorResponse(this.path);

  factory LookupActorResponse.unpack(Uint8List data) {
    final deserializer = Deserializer(data);
    final String? path = deserializer.decode();
    return LookupActorResponse(path != null ? Uri.parse(path) : null);
  }

  @override
  Uint8List pack() {
    final serializer = Serializer();
    serializer.encode(path?.toString());
    return serializer.takeBytes();
  }

  @override
  String toString() => 'LookupActorResponse(path=$path)';
}
