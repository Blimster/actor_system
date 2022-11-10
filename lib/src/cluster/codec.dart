import 'dart:async';
import 'dart:typed_data';

import 'package:actor_system/src/cluster/messages/create_actor.dart';
import 'package:actor_system/src/cluster/messages/lookup_actor.dart';
import 'package:actor_system/src/cluster/messages/send_message.dart';
import 'package:actor_system/src/cluster/protocol.dart';
import 'package:actor_system/src/cluster/ser_des.dart';
import 'package:actor_system/src/cluster/stream_reader.dart';
import 'package:msgpack_dart/msgpack_dart.dart';
import 'package:stream_channel/stream_channel.dart';

PackableData _createMessage(ProtocolMessageType messageType, String messageName, Uint8List messageData, SerDes serDes) {
  switch (messageName) {
    case createActorMessageName:
      switch (messageType) {
        case ProtocolMessageType.request:
          return CreateActorRequest.unpack(messageData);
        case ProtocolMessageType.response:
          return CreateActorResponse.unpack(messageData);
        default:
          throw StateError('protocol message type $messageType is not supported');
      }
    case lookupActorMessageName:
      switch (messageType) {
        case ProtocolMessageType.request:
          return LookupActorRequest.unpack(messageData);
        case ProtocolMessageType.response:
          return LookupActorResponse.unpack(messageData);
        default:
          throw StateError('protocol message type $messageType is not supported');
      }
    case sendMessageMessageName:
      switch (messageType) {
        case ProtocolMessageType.request:
          return SendMessageRequest.unpack(messageData, serDes);
        case ProtocolMessageType.response:
          return SendMessageResponse.unpack(messageData);
        default:
          throw StateError('protocol message type $messageType is not supported');
      }
    default:
      throw StateError('protocol message name $messageName is not supported');
  }
}

void _writeToSink(
  Sink<List<int>> sink,
  ProtocolMessageType messageType,
  String messageName,
  String correlationId,
  Uint8List messageData,
) {
  final serializer = Serializer();
  serializer.encode(messageType.name);
  serializer.encode(messageName);
  serializer.encode(correlationId);
  serializer.encode(messageData);
  final content = serializer.takeBytes();
  sink.add(_serializeLength(content.length));
  sink.add(content);
}

Uint8List _serializeLength(int value) {
  final bytes = Uint8List(4);
  bytes.buffer.asByteData().setInt32(0, value, Endian.big);
  return bytes;
}

class MessageChannel extends StreamChannelMixin<ProtocolMessage> {
  final StreamReader _reader;
  final Sink<List<int>> _writer;
  final SerDes _serDes;
  final StreamController<ProtocolMessage> _outController = StreamController();
  final StreamController<ProtocolMessage> _inController = StreamController();

  MessageChannel(this._reader, this._writer, this._serDes) {
    _outController.stream.listen((event) {
      _writeToSink(
        _writer,
        event.type,
        event.name,
        event.correlationId,
        event.data.pack(),
      );
    });

    _startReading();
  }

  void _startReading() {
    Future(() async {
      while (true) {
        final message = await _reader.receiveData();
        final deserializer = Deserializer(message);
        final ProtocolMessageType messageType = ProtocolMessageType.values.byName(deserializer.decode());
        final String messageName = deserializer.decode();
        final String correlationId = deserializer.decode();
        final Uint8List messageData = deserializer.decode();
        _inController.add(ProtocolMessage(
            messageType,
            messageName,
            correlationId,
            _createMessage(
              messageType,
              messageName,
              messageData,
              _serDes,
            )));
      }
    });
  }

  @override
  StreamSink<ProtocolMessage> get sink => _outController.sink;

  @override
  Stream<ProtocolMessage> get stream => _inController.stream;
}
