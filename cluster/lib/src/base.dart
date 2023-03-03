import 'dart:io';

String systemName(String nodeId, int workerId) => '${nodeId}_$workerId';

String getNodeId(String host) {
  int separatorIndex = host.lastIndexOf('_');
  if (separatorIndex == -1) {
    return host;
  }
  return host.substring(0, separatorIndex);
}

int getWorkerId(String host) {
  int separatorIndex = host.lastIndexOf('_');
  if (separatorIndex == -1) {
    return 0;
  }
  return int.parse(host.substring(separatorIndex + 1));
}

extension SocketExtension on Socket {
  /// Returns the address and port of this [Socket] as a [String] in the form
  /// "host:port". A closed socket is handled by this method.
  String addressToString() {
    try {
      return '${address.address}:$port';
    } catch (e) {
      return 'address unknown (maybe closed)';
    }
  }
}
