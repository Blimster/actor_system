part of actor_system;

class ActorRef {
  final int _maxMailBoxSize;
  final Queue<Object> _mailbox = Queue();
  final Map<Type, dynamic> _handlers;
  bool isProcessing = false;

  ActorRef._(this._maxMailBoxSize, this._handlers);

  void send(Object message) {
    if (message == null) {
      throw new ArgumentError('message is null!');
    }
    if (!_handlers.containsKey(message.runtimeType)) {
      throw new ArgumentError('the actor can not handle messages of type ${message.runtimeType}! supported type are ${_handlers.keys.join(', ')}.');
    }
    if (_mailbox.length >= _maxMailBoxSize) {
      throw new Exception('mailbox is full! max size is $_maxMailBoxSize.');
    }

    _mailbox.addLast(message);
    _handleMessage();
  }

  void _handleMessage() {
    Future(() async {
      if (!isProcessing && _mailbox.isNotEmpty) {
        try {
          isProcessing = true;
          final message = _mailbox.removeFirst();
          final handler = _handlers[message.runtimeType];
          final result = handler(null, message);
          if (result is Future) {
            await result;
          }
          _handleMessage();
        } finally {
          isProcessing = false;
        }
      }
    });
  }
}
