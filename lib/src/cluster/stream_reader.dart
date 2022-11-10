import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:actor_system/src/cluster/ring_buffer.dart';

Future<int> _deserializeSize(StreamReader reader) async {
  final list = await reader._takeCount(4);
  return ByteData.sublistView(list).getInt32(0, Endian.big);
}

class StreamReader {
  final Stream<List<int>> _stream;
  final _controller = StreamController<void>.broadcast();
  final RingBuffer _buffer;
  bool _done = false;

  StreamReader(this._stream, {int bufferSize = 1024 * 1024, void Function()? onDone})
      : _buffer = RingBuffer(bufferSize);

  void _onData(List<int> data) {
    _buffer.addAll(data);
    _controller.add(null);
  }

  void _onDone() {
    _done = true;
    _controller.add(null);
  }

  StreamSubscription<List<int>> bind({Function? onError, void onDone()?, bool? cancelOnError}) {
    return _stream.listen(
      _onData,
      onDone: () {
        _onDone();
        onDone?.call();
      },
      onError: onError,
      cancelOnError: cancelOnError,
    );
  }

  Future<Uint8List> _takeCount(int count) {
    final completer = Completer<Uint8List>();
    final buffer = Uint8List(count);
    final subscription = _controller.stream.listen(null);
    int index = 0;

    subscription.onData((_) {
      if (_done) {
        completer.completeError(StateError('Stream closed'));
        return;
      }
      final dataLength = min(this._buffer.length, count - index);
      buffer.setAll(index, this._buffer.read(dataLength));
      index += dataLength;
      if (index == count) {
        subscription.cancel();
        completer.complete(buffer);
      }
    });
    _controller.add(null);

    return completer.future;
  }

  Future<Uint8List> receiveData() async {
    final size = await _deserializeSize(this);
    return _takeCount(size);
  }
}
