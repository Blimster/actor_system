import 'dart:typed_data';

import 'package:actor_cluster/src/protocol.dart';
import 'package:msgpack_dart/msgpack_dart.dart';

class WorkerInfo implements PackableData {
  final int workerId;
  final double load;
  final List<String> actorsAdded;
  final List<String> actorsRemoved;

  WorkerInfo(this.workerId, this.load, this.actorsAdded, this.actorsRemoved);

  factory WorkerInfo.unpack(Uint8List data) {
    final deserializer = Deserializer(data);
    return WorkerInfo(
      deserializer.decode(),
      deserializer.decode(),
      deserializer.decode().cast<String>(),
      deserializer.decode().cast<String>(),
    );
  }

  @override
  Uint8List pack() {
    final serializer = Serializer();
    serializer.encode(workerId);
    serializer.encode(load);
    serializer.encode(actorsAdded);
    serializer.encode(actorsRemoved);
    return serializer.takeBytes();
  }

  @override
  String toString() =>
      'WorkerInfo(workerId=$workerId, load=$load, actorsAdded=$actorsAdded, actorsRemoved=$actorsRemoved)';
}
