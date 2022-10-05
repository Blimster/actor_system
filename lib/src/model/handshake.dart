import 'dart:convert';

final handshakeRequestType = 'HANDSHAKE_REQ';
final handshakeResponseType = 'HANDSHAKE_RES';

class HandshakeRequest {
  final String secret;
  final String nodeId;

  HandshakeRequest(this.secret, this.nodeId);

  factory HandshakeRequest.fromJson(String jsonString) {
    final jsonMap = json.decode(jsonString);
    return HandshakeRequest(
      jsonMap['secret'],
      jsonMap['nodeId'],
    );
  }

  String toJson() => json.encode({'secret': secret, 'nodeId': nodeId});
}

class HandshakeResponse {
  final String nodeId;

  HandshakeResponse(this.nodeId);

  factory HandshakeResponse.fromJson(String jsonString) => HandshakeResponse(
        json.decode(jsonString)['nodeId'],
      );

  String toJson() => json.encode({'nodeId': nodeId});
}
