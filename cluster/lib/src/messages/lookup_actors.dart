import 'dart:typed_data';

import 'package:actor_cluster/src/protocol.dart';
import 'package:msgpack_dart/msgpack_dart.dart';

class LookupActorsRequest implements PackableData {
  final Uri path;

  LookupActorsRequest(this.path);

  factory LookupActorsRequest.unpack(Uint8List data) {
    final deserializer = Deserializer(data);
    return LookupActorsRequest(
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
  String toString() => 'LookupActorsRequest(path=$path)';
}

class LookupActorsResponse implements PackableData {
  final List<Uri> paths;

  LookupActorsResponse(this.paths);

  factory LookupActorsResponse.unpack(Uint8List data) {
    final deserializer = Deserializer(data);
    final List paths = deserializer.decode();
    return LookupActorsResponse(paths.map((e) => Uri.parse(e)).toList());
  }

  @override
  Uint8List pack() {
    final serializer = Serializer();
    serializer.encode(paths.map((e) => e.toString()));
    return serializer.takeBytes();
  }

  @override
  String toString() => 'LookupActorsResponse(path=$paths)';
}
