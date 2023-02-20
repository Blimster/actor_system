final handshakeRequestType = 'HANDSHAKE_REQ';
final handshakeResponseType = 'HANDSHAKE_RES';

class HandshakeNode {
  final String nodeId;
  final String host;
  final int port;

  HandshakeNode(this.nodeId, this.host, this.port);

  factory HandshakeNode.fromJson(Map<String, dynamic> json) {
    return HandshakeNode(
      json['nodeId'],
      json['host'],
      json['port'],
    );
  }

  Map<String, dynamic> toJson() => {
        'nodeId': nodeId,
        'host': host,
        'port': port,
      };
}

class HandshakeRequest {
  final String correlationId;
  final List<String> seedNodeIds;
  final String secret;
  final HandshakeNode node;
  final String uuid;
  final int workers;
  final List<String> tags;
  final bool clusterInitialized;

  HandshakeRequest(
    this.correlationId,
    this.seedNodeIds,
    this.secret,
    this.node,
    this.uuid,
    this.workers,
    this.tags,
    this.clusterInitialized,
  );

  factory HandshakeRequest.fromJson(Map<String, dynamic> json) {
    return HandshakeRequest(
      json['correlationId'],
      (json['seedNodeIds'] as List).map((e) => e.toString()).toList(),
      json['secret'],
      HandshakeNode.fromJson(json['node']),
      json['uuid'],
      json['workers'],
      (json['tags'] as List).map((e) => e.toString()).toList(),
      json['clusterInitialized'],
    );
  }

  Map<String, dynamic> toJson() => {
        'correlationId': correlationId,
        'seedNodeIds': seedNodeIds,
        'secret': secret,
        'node': node.toJson(),
        'uuid': uuid,
        'workers': workers,
        'tags': tags,
        'clusterInitialized': clusterInitialized,
      };
}

class HandshakeResponse {
  final String correlationId;
  final HandshakeNode node;
  final String uuid;
  final int workers;
  final List<String> tags;
  final List<HandshakeNode> connectedAdditionalNodes;
  final bool clusterInitialized;

  HandshakeResponse(
    this.correlationId,
    this.node,
    this.uuid,
    this.workers,
    this.tags,
    this.connectedAdditionalNodes,
    this.clusterInitialized,
  );

  factory HandshakeResponse.fromJson(Map<String, dynamic> json) {
    return HandshakeResponse(
      json['correlationId'],
      HandshakeNode.fromJson(json['node']),
      json['uuid'],
      json['workers'],
      (json['tags'] as List).map((e) => e.toString()).toList(),
      (json['connectedAdditionalNodes'] as List).map((e) => HandshakeNode.fromJson(e)).toList(),
      json['clusterInitialized'],
    );
  }

  Map<String, dynamic> toJson() => {
        'correlationId': correlationId,
        'node': node.toJson(),
        'uuid': uuid,
        'workers': workers,
        'tags': tags,
        'connectedAdditionalNodes': connectedAdditionalNodes.map((e) => e.toJson()).toList(),
        'clusterInitialized': clusterInitialized,
      };
}
