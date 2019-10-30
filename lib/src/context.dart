part of actor_system;

///
///
///
class ActorContext {
  final Uri _path;
  final Map<Uri, ActorRef> _actorRefs;

  ActorContext._(this._path, this._actorRefs);

  ///
  ///
  ///
  Uri get path => _path;

  ///
  ///
  ///
  Future<ActorRef> createActor(Uri path, ActorFactory factory) async {
    // validate path param
    if (path == null) {
      throw new ArgumentError.notNull('path');
    }
    if (!path.hasAbsolutePath) {
      throw new ArgumentError('parameter [path] must be an absolte uri!');
    }

    if (path.pathSegments.last.isEmpty) {
      // path ends with a slash (/). add an segment to the path, so the path is
      // unique
      var temp = path.resolve(new Uuid().v4());
      while (_actorRefs.containsKey(temp)) {
        temp = path.resolve(new Uuid().v4());
      }
      path = temp;
    } else {
      // path does not end with a slash (/). is the path already in use?
      if (_actorRefs.containsKey(path)) {
        throw new ArgumentError.value(path?.path, 'path', 'path already in use!');
      }
    }

    // call the factory to create the actor logic
    final factoryContext = FactoryContext._();
    final result = factory(factoryContext);
    if (result is Future) {
      await result;
    }

    // create, store and return the actor ref
    final actorRef = ActorRef._(path, 1000, _actorRefs, factoryContext._handlers);
    _actorRefs[path] = actorRef;
    return actorRef;
  }

  ///
  ///
  ///
  Future<ActorRef> lookupActor(Uri path) async {
    return _actorRefs[path];
  }
}

///
///
///
typedef MessageHandler<T> = FutureOr<void> Function(ActorContext context, T message);

///
///
///
typedef ActorFactory = FutureOr<void> Function(FactoryContext context);

///
///
///
class FactoryContext {
  final Map<Type, dynamic> _handlers = {};

  FactoryContext._();

  ///
  ///
  ///
  void registerMessageHandler<T>(MessageHandler<T> handler) {
    final messageType = _TypeOf<T>().get();

    if (_handlers.containsKey(messageType)) {
      throw StateError('a message handler for type $messageType is already registered!');
    }
    _handlers[messageType] = handler;
  }
}

class _TypeOf<T> {
  const _TypeOf();

  Type get() => T;
}
