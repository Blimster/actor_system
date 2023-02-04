import 'dart:convert';

final handshakeRequestType = 'HANDSHAKE_REQ';
final handshakeResponseType = 'HANDSHAKE_RES';

class HandshakeRequest {
  final String correlationId;
  final String secret;
  final String nodeId;
  final String uuid;
  final int workers;

  HandshakeRequest(
    this.correlationId,
    this.secret,
    this.nodeId,
    this.uuid,
    this.workers,
  );

  factory HandshakeRequest.fromJson(String jsonString) {
    final jsonMap = json.decode(jsonString);
    return HandshakeRequest(
      jsonMap['correlationId'],
      jsonMap['secret'],
      jsonMap['nodeId'],
      jsonMap['uuid'],
      jsonMap['workers'],
    );
  }

  String toJson() => json.encode({
        'correlationId': correlationId,
        'secret': secret,
        'nodeId': nodeId,
        'uuid': uuid,
        'workers': workers,
      });
}

class HandshakeResponse {
  final String correlationId;
  final String nodeId;
  final String uuid;
  final int workers;

  HandshakeResponse(this.correlationId, this.nodeId, this.uuid, this.workers);

  factory HandshakeResponse.fromJson(String jsonString) => HandshakeResponse(
        json.decode(jsonString)['correlationId'],
        json.decode(jsonString)['nodeId'],
        json.decode(jsonString)['uuid'],
        json.decode(jsonString)['workers'],
      );

  String toJson() => json.encode({
        'correlationId': correlationId,
        'nodeId': nodeId,
        'uuid': uuid,
        'workers': workers,
      });
}
