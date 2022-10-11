import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:actor_system/src/cluster/stream_reader.dart';

List<int> _serializeSize(int value) {
  final bytes = Uint8List(4);
  bytes.buffer.asByteData().setInt32(0, value, Endian.big);
  return bytes.toList();
}

class SocketMessage {
  final String type;
  final String content;

  SocketMessage(this.type, this.content);
}

class SocketAdapter {
  final Socket _socket;
  final Stream<Uint8List> _stream;
  late StreamReader _streamReader;

  SocketAdapter(this._socket) : _stream = _socket.asBroadcastStream() {
    _streamReader = StreamReader(_stream);
  }

  Future<void> sendMessage(SocketMessage message) async {
    final type = utf8.encode(message.type);
    final content = utf8.encode(message.content);

    _socket.add([
      ..._serializeSize(type.length),
      ...type,
      ..._serializeSize(content.length),
      ...content,
    ]);
    await _socket.flush();
    return null;
  }

  Future<SocketMessage> receiveData() async {
    final type = await _streamReader.receiveData();
    final content = await _streamReader.receiveData();
    return SocketMessage(
      utf8.decode(type),
      utf8.decode(content),
    );
  }

  set onClose(void Function() onClose) {
    _stream.listen(null, onDone: onClose);
  }

  void close() {
    _socket.destroy();
  }
}
