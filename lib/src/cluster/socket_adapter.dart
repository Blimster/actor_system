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
  final Socket socket;
  final StreamReader streamReader;

  SocketAdapter(this.socket) : streamReader = StreamReader(socket);

  void bind({Function? onError, void onDone()?, bool? cancelOnError}) {
    streamReader.bind(onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  Future<void> sendMessage(SocketMessage message) async {
    final type = utf8.encode(message.type);
    final content = utf8.encode(message.content);

    socket.add([
      ..._serializeSize(type.length),
      ...type,
      ..._serializeSize(content.length),
      ...content,
    ]);
    await socket.flush();
    return null;
  }

  Future<SocketMessage> receiveData() async {
    final type = await streamReader.receiveData();
    final content = await streamReader.receiveData();
    return SocketMessage(
      utf8.decode(type),
      utf8.decode(content),
    );
  }

  void close() {
    socket.destroy();
  }
}
