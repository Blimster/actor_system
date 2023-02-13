import 'dart:math';

import 'package:actor_cluster/src/node.dart';
import 'package:actor_system/actor_system.dart';

ClusterContext createClusterContext(LocalNode localNode) {
  return ClusterContext._(localNode);
}

class ClusterContext implements BaseContext {
  final LocalNode _localNode;

  ClusterContext._(this._localNode);

  @override
  Future<ActorRef> createActor(
    Uri path, {
    ActorFactory? factory,
    int? mailboxSize,
    bool? useExistingActor,
    bool sendInit = false,
  }) async {
    assert(factory == null, 'factory is always ignored in cluster mode');

    final result = await _localNode.createActor(path, mailboxSize, useExistingActor);
    if (sendInit) {
      await result.send(initMsg);
    }
    return result;
  }

  @override
  Future<ActorRef?> lookupActor(Uri path) {
    return _localNode.lookupActor(path);
  }

  @override
  Future<List<ActorRef>> lookupActors(Uri path) {
    return _localNode.lookupActors(path);
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
