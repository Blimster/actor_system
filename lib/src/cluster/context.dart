import 'dart:math';

import 'package:actor_system/actor_system.dart';
import 'package:actor_system/src/cluster/node.dart';

ClusterContext createContext(List<Node> nodes) {
  return ClusterContext._(nodes);
}

class ClusterContext implements BaseContext {
  final List<Node> nodes;

  ClusterContext._(this.nodes);

  @override
  Future<ActorRef> createActor(
    Uri path, {
    ActorFactory? factory,
    int? mailboxSize,
    bool useExistingActor = false,
  }) {
    assert(factory == null, 'factory is always ignored in cluster mode');

    return findNode(
      nodes,
      path,
    ).createActor(
      path,
      mailboxSize,
      useExistingActor,
    );
  }

  @override
  Future<ActorRef?> lookupActor(Uri path) {
    throw UnimplementedError();
  }
}

Node findNode(List<Node> nodes, Uri path) {
  Node? node;
  if (path.host.isEmpty) {
    final Random random = Random();
    final nodeIndex = random.nextInt(nodes.length);
    return nodes[nodeIndex];
  } else if (path.host == localSystem) {
    try {
      node = nodes.firstWhere((node) => node.isLocal);
    } on StateError {
      // ignore: no node found
    }
  } else {
    try {
      node = nodes.firstWhere((node) => path.host == node.nodeId);
    } on StateError {
      // ignore: no node found
    }
  }

  if (node == null) {
    throw ArgumentError.value(path.host, 'path.host', 'node not found');
  }

  if (!node.validateWorkerId(path.port)) {
    throw ArgumentError.value(path.host, 'path.port', 'workder not found');
  }

  return node;
}
