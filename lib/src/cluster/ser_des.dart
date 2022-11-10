import 'dart:typed_data';

abstract class SerDes {
  Uint8List serialize(Object? message);
  Object? deserialize(Uint8List data);
}
