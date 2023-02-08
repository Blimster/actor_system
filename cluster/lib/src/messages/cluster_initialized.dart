import 'dart:typed_data';

import 'package:actor_cluster/src/protocol.dart';
import 'package:msgpack_dart/msgpack_dart.dart';

class ClusterInitialized implements PackableData {
  final String nodeId;

  ClusterInitialized(this.nodeId);

  factory ClusterInitialized.unpack(Uint8List data) {
    final deserializer = Deserializer(data);
    return ClusterInitialized(
      deserializer.decode(),
    );
  }

  @override
  Uint8List pack() {
    final serializer = Serializer();
    serializer.encode(nodeId);
    return serializer.takeBytes();
  }

  @override
  String toString() => 'ClusterInitialized(nodeId=$nodeId)';
}
