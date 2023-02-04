import 'dart:io';

String systemName(String nodeId, int workerId) => '${nodeId}_$workerId';

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
