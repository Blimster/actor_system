part of actor_system;

///
/// 
/// 
class ActorRef {
  final Uri path;
  final int _maxMailBoxSize;
  final Queue<Object> _mailbox = Queue();
  final Map<Uri, ActorRef> _actorRefs;
  final Map<Type, dynamic> _handlers;
  bool _isProcessing = false;

  ActorRef._(this.path, this._maxMailBoxSize, this._actorRefs, this._handlers);

  ///
  /// 
  /// 
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
      if (!_isProcessing && _mailbox.isNotEmpty) {
        try {
          _isProcessing = true;
          final message = _mailbox.removeFirst();
          final handler = _handlers[message.runtimeType];
          final result = handler(ActorContext._(path, _actorRefs), message);
          if (result is Future) {
            await result;
          }
          _handleMessage();
        } finally {
          _isProcessing = false;
        }
      }
    });
  }
}
