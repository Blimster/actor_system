import 'dart:typed_data';

import 'package:actor_cluster/src/protocol.dart';
import 'package:msgpack_dart/msgpack_dart.dart';

class WorkerInfo implements PackableData {
  final int workerId;
  final double load;
  final List<Uri> actorsAdded;
  final List<Uri> actorsRemoved;

  WorkerInfo(this.workerId, this.load, this.actorsAdded, this.actorsRemoved);

  factory WorkerInfo.unpack(Uint8List data) {
    final deserializer = Deserializer(data);
    return WorkerInfo(
      deserializer.decode(),
      deserializer.decode(),
      deserializer.decode().cast<String>().map(Uri.parse).toList(),
      deserializer.decode().cast<String>().map(Uri.parse).toList(),
    );
  }

  @override
  Uint8List pack() {
    final serializer = Serializer();
    serializer.encode(workerId);
    serializer.encode(load);
    serializer.encode(actorsAdded.map((e) => e.toString()));
    serializer.encode(actorsRemoved.map((e) => e.toString()));
    return serializer.takeBytes();
  }

  @override
  String toString() =>
      'WorkerInfo(workerId=$workerId, load=$load, actorsAdded=$actorsAdded, actorsRemoved=$actorsRemoved)';
}
