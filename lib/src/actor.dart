part of actor_system;

/// An actor is a function that processes messages. This function should never
/// be called directly. It should only be used as a parameter to
/// [ActorContext.createActor].
///
/// If the processing of a message fails, the actor will be disposed and a new
/// one will be created using the factory.
typedef Actor = FutureOr<void> Function(Object message);

/// A factory to create an actor. The given context can be used to communicate
/// with other actors of the same acor system.
typedef ActorFactory = Actor Function(ActorContext context);

/// A context for an actor. The context is provided to the actor for
class ActorContext {
  final Uri _path;
  final Map<Uri, ActorRef> _actorRefs;

  ActorContext._(this._path, this._actorRefs);

  /// The path of the actor. Every actor in a system has an unique path.
  Uri get path => _path;

  /// Creates an actor at the given path.
  ///
  /// The path for an actor must be unique. It is an error to create a new actor
  /// with a path, an existing actor already is created with in the same actor
  /// system. If the given path ends with a slash (/), the path is extended by
  /// an uuid.
  ///
  /// The given [actorFactory] is called to create the actor for the given path.
  ///
  /// If [useExistingActor] is set to true, the provided path ends with a slash
  /// and an actor with the path already exists, the existing actor is return
  /// instead a newly create actor.
  Future<ActorRef> createActor(Uri path, ActorFactory actorFactory, {bool useExistingActor = false}) async {
    if (!path.hasAbsolutePath) {
      throw ArgumentError('parameter [path] must be an absolte uri!');
    }

    if (path.pathSegments.last.isEmpty) {
      // path ends with a slash (/). add an segment to the path, so the path is
      // unique
      var temp = path.resolve(Uuid().v4());
      while (_actorRefs.containsKey(temp)) {
        temp = path.resolve(Uuid().v4());
      }
      path = temp;
    } else {
      // path does not end with a slash (/). is the path already in use?
      final existing = _actorRefs[path];
      if (existing != null) {
        if (useExistingActor) {
          return existing;
        } else {
          throw ArgumentError.value(path.path, 'path', 'path already in use!');
        }
      }
    }

    // create, store and return the actor ref
    final actorRef = ActorRef._(path, 1000, actorFactory, ActorContext._(path, _actorRefs));
    _actorRefs[path] = actorRef;
    return actorRef;
  }

  /// Looks up an actor reference using the given path. If no actor exists for
  /// that path, null is returned.
  Future<ActorRef?> lookupActor(Uri path) async {
    return _actorRefs[path];
  }
}

/// A reference to an actor. The only way to communicate with an actor is to
/// send messages to it using the API of the [ActorRef].
class ActorRef {
  final Uri path;
  final int _maxMailBoxSize;
  final Queue<Object> _mailbox = Queue();
  final ActorFactory _factory;
  final ActorContext _context;
  Actor _actor;
  bool _isProcessing = false;

  ActorRef._(this.path, this._maxMailBoxSize, this._factory, this._context) : _actor = _factory(_context);

  /// Sends a message to the actor referenced by this
  /// [ActorRef]. It is guaranteed, that an actor processes
  /// only one message at a time.
  ///
  /// If a message is sent to an actor that currently
  /// processes another message, the new message is put
  /// into the mailbox of the actor. Messages are
  /// processed in the order they arrive at the actor.
  ///
  /// If an error occurs while a message is processed and
  /// is not handled by the actor itself, the actor is
  /// thrown away and recreated using the factory provided
  /// when the actor was created. The messages in mailbox
  /// of the actor remain.
  void send(Object message) {
    if (_mailbox.length >= _maxMailBoxSize) {
      throw Exception('mailbox is full! max size is $_maxMailBoxSize.');
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

          final result = _actor(message);
          if (result is Future) {
            await result;
          }
        } catch (error) {
          _actor = _factory(_context);
        } finally {
          _isProcessing = false;
          _handleMessage();
        }
      }
    });
  }
}
