import 'dart:typed_data';

class RingBuffer {
  final Uint8List _buffer;
  int _size = 0;
  int _writeOffset = 0;
  int _readOffset = 0;

  RingBuffer(int capacity)
      : assert(capacity > 0),
        _buffer = Uint8List(capacity);

  void addAll(List<int> data) {
    if (remainingCapacity < data.length) {
      throw StateError('Buffer overflow!');
    }
    _size += data.length;

    if (data.length < _buffer.length - _writeOffset) {
      _buffer.setAll(_writeOffset, data);
      _writeOffset += data.length;
    } else {
      final firstPart = _buffer.length - _writeOffset;
      final secondPart = data.length - firstPart;
      _buffer.setAll(_writeOffset, data.sublist(0, firstPart));
      _buffer.setAll(0, data.sublist(firstPart, firstPart + secondPart));
      _writeOffset = secondPart;
    }
  }

  Uint8List read(int count) {
    if (count > _size) {
      throw StateError('Buffer underflow!');
    }
    _size -= count;

    if (count < _buffer.length - _readOffset) {
      final result = _buffer.sublist(_readOffset, _readOffset + count);
      _readOffset += count;
      return result;
    } else {
      final firstPart = _buffer.length - _readOffset;
      final secondPart = count - firstPart;
      final result = Uint8List(count);
      result.setAll(0, _buffer.sublist(_readOffset, _readOffset + firstPart));
      result.setAll(firstPart, _buffer.sublist(0, secondPart));
      _readOffset = secondPart;
      return result;
    }
  }

  int get length => _size;

  bool get isEmpty => !isNotEmpty;

  bool get isNotEmpty => _size > 0;

  int get capacity => _buffer.length;

  int get remainingCapacity => capacity - length;
}
