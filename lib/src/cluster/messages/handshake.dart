import 'dart:convert';

final handshakeRequestType = 'HANDSHAKE_REQ';
final handshakeResponseType = 'HANDSHAKE_RES';

class HandshakeRequest {
  final String secret;
  final String nodeId;
  final String uuid;

  HandshakeRequest(this.secret, this.nodeId, this.uuid);

  factory HandshakeRequest.fromJson(String jsonString) {
    final jsonMap = json.decode(jsonString);
    return HandshakeRequest(
      jsonMap['secret'],
      jsonMap['nodeId'],
      jsonMap['uuid'],
    );
  }

  String toJson() => json.encode({
        'secret': secret,
        'nodeId': nodeId,
        'uuid': uuid,
      });
}

class HandshakeResponse {
  final String nodeId;
  final String uuid;

  HandshakeResponse(this.nodeId, this.uuid);

  factory HandshakeResponse.fromJson(String jsonString) => HandshakeResponse(
        json.decode(jsonString)['nodeId'],
        json.decode(jsonString)['uuid'],
      );

  String toJson() => json.encode({
        'nodeId': nodeId,
        'uuid': uuid,
      });
}
