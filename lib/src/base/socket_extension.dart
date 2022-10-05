import 'dart:io';

extension SocketExtension on Socket {
  String addressToString() {
    try {
      return '${address.address}:$port';
    } catch (e) {
      return 'address unknown (maybe closed)';
    }
  }
}
