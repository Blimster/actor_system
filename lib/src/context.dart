part of actor_system;

class ActorContext {
  Future<ActorRef> createActor(Uri path, ActorFactory factory) async {
    final factoryContext = FactoryContext._();
    final result = factory(factoryContext);
    if (result is Future) {
      await result;
    }
    return ActorRef._(1000, factoryContext._handlers);
  }
}

typedef MessageHandler<T> = FutureOr<void> Function(ActorContext context, T message);
typedef ActorFactory = FutureOr<void> Function(FactoryContext context);

///
///
///
class FactoryContext {
  final Map<Type, dynamic> _handlers = {};

  FactoryContext._();

  void registerMessageHandler<T>(MessageHandler<T> handler) {
    final messageType = TypeLiteral<T>().get();

    if (_handlers.containsKey(messageType)) {
      throw StateError('a message handler for type $messageType is already registered!');
    }
    _handlers[messageType] = handler;
  }
}
