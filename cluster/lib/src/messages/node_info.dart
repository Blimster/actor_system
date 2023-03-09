import 'dart:typed_data';

import 'package:actor_cluster/src/protocol.dart';
import 'package:msgpack_dart/msgpack_dart.dart';

class NodeInfo implements PackableData {
  final String nodeId;
  final double load;
  final List<Uri> actorsAdded;
  final List<Uri> actorsRemoved;

  NodeInfo(this.nodeId, this.load, this.actorsAdded, this.actorsRemoved);

  factory NodeInfo.unpack(Uint8List data) {
    final deserializer = Deserializer(data);
    return NodeInfo(
      deserializer.decode(),
      deserializer.decode(),
      (deserializer.decode() as List).map((e) => Uri.parse(e.toString())).toList(),
      (deserializer.decode() as List).map((e) => Uri.parse(e.toString())).toList(),
    );
  }

  @override
  Uint8List pack() {
    final serializer = Serializer();
    serializer.encode(nodeId);
    serializer.encode(load);
    serializer.encode(actorsAdded.map((e) => e.toString()));
    serializer.encode(actorsRemoved.map((e) => e.toString()));
    return serializer.takeBytes();
  }

  @override
  String toString() => 'NodeInfo(nodeId=$nodeId, load=$load, actorsAdded=$actorsAdded, actorsRemoved=$actorsRemoved)';
}
