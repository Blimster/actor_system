import 'dart:async';
import 'dart:collection';

import 'package:actor_system/src/base/reference.dart';
import 'package:actor_system/src/base/uri.dart';

/// An actor is a function that processes messages. This function should never
/// be called directly. It should only be used as a parameter to
/// [ActorContext.createActor].
///
/// If the processing of a message fails, the actor will be disposed and a new
/// one will be created using the factory.
typedef Actor = FutureOr<void> Function(ActorContext context, Object? message);

/// Looks up an actor by the given [Uri].
typedef ActorLookup = FutureOr<ActorRef?> Function(Uri uri);

/// A factory to create an actor. The given path can be used to determine the
/// type of the actor to create.
typedef ActorFactory = Actor Function(Uri path);

/// A context for an actor. The context is provided to the actor for
class ActorContext {
  final String? name;
  final Uri _path;
  final Map<String, ActorRef> _actorRefs;
  final Map<String, ActorFactory> _factories;
  NullableRef<ActorLookup> _externalLookup;
  ActorRef? _current;
  ActorRef? _replyTo;

  ActorContext._(this.name, this._path, this._actorRefs, this._factories,
      this._externalLookup);

  /// The path of the actor. Every actor in a system has an unique path.
  Uri get path => _path;

  /// The current reference.
  ActorRef get current {
    final current = _current;
    if (current != null) {
      return current;
    }
    throw StateError('No current actor reference!');
  }

  /// The reference to the actor to reply to.
  ActorRef? get replyTo => _replyTo;

  /// Registers an [ActorFactory] for the given [path]. The factory is used to
  /// create a new actor if a call to [ActorContext.createActor] has no factory
  /// and the path matches.
  void registerFactory(Uri path, ActorFactory factory) {
    _factories[path.path] = factory;
  }

  /// Creates an actor at the given path.
  ///
  /// The path for an actor must be unique. It is an error to create a new actor
  /// with a path, an existing actor already is created with in the same actor
  /// system. If the given path ends with a slash (/), the path is extended by
  /// an uuid.
  ///
  /// The given [ActorFactory] is called to create the actor for the given path.
  /// If no factory is provided, a registered factory is used. If such factory
  /// does not exists, an error is thrown.
  ///
  /// If [useExistingActor] is set to true, the provided path ends with a slash
  /// and an actor with the path already exists, the existing actor is return
  /// instead a newly create actor.
  Future<ActorRef> createActor(
    Uri path, {
    ActorFactory? factory,
    bool useExistingActor = false,
  }) async {
    if (!path.hasAbsolutePath) {
      throw ArgumentError('parameter [path] must be an absolte uri!');
    }

    if (path.pathSegments.last.isNotEmpty) {
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

    // search for registered factory if no factory is provided
    final actorFactory = factory ?? _factories[path];
    if (actorFactory == null) {
      throw ArgumentError.value(path.path, 'path', 'no factory for path!');
    }

    // create, store and return the actor ref
    final actorPath = completeActorPath(path, _actorRefs.keys);
    final actorRef = ActorRef._(
        actorPath,
        1000,
        actorFactory,
        ActorContext._(
          name,
          actorPath,
          _actorRefs,
          _factories,
          _externalLookup,
        ));
    _actorRefs[actorPath.path] = actorRef;

    return actorRef;
  }

  /// Looks up an actor reference using the given path. If no actor exists for
  /// that path, null is returned.
  Future<ActorRef?> lookupActor(Uri path) async {
    if (path.host.isEmpty || path.host == name) {
      return _actorRefs[path.path];
    }
    return _externalLookup.value?.call(path);
  }
}

/// An [ActorSystem] is a collection of actors, the can communicate with each
/// other. An actor can only create or lookup actors in the same [ActorSystem].
class ActorSystem extends ActorContext {
  /// Creates a new [ActorSystem].
  ActorSystem({String? name})
      : super._(name, Uri.parse('/'), {}, {}, NullableRef());

  /// Sets the external lookup function. This function is used to lookup actors
  /// in an external [ActorSystem].
  set externalLookup(ActorLookup? lookup) => _externalLookup.value = lookup;
}

/// A reference to an actor. The only way to communicate with an actor is to
/// send messages to it using the API of the [ActorRef].
class ActorRef {
  final Uri path;
  final int _maxMailBoxSize;
  final Queue<Envelope> _mailbox = Queue();
  final ActorFactory _factory;
  final ActorContext _context;
  Actor _actor;
  bool _isProcessing = false;

  ActorRef._(this.path, this._maxMailBoxSize, this._factory, this._context)
      : _actor = _factory(path);

  /// Sends a message to the actor referenced by this
  /// [ActorRef]. It is guaranteed, that an actor processes
  /// only one message at a time.
  ///
  /// If a message is sent to an actor that currently
  /// processes another message, the new message is put
  /// into the mailbox of the actor. Messages are
  /// processed in the order they arrive at the actor.
  ///
  /// The returned [Future] completes when the message was
  /// successfully added to the actors mailbox.
  ///
  /// If an error occurs while a message is processed and
  /// is not handled by the actor itself, the actor is
  /// thrown away and recreated using the factory provided
  /// when the actor was created. The messages in mailbox
  /// of the actor remain.
  Future<void> send(Object? message, {ActorRef? replyTo}) async {
    if (_mailbox.length >= _maxMailBoxSize) {
      throw Exception('mailbox is full! max size is $_maxMailBoxSize.');
    }
    _mailbox.addLast(Envelope(message, replyTo));
    _handleMessage();

    // message was added to mailbox
    return null;
  }

  void _handleMessage() {
    Future(() async {
      if (!_isProcessing && _mailbox.isNotEmpty) {
        try {
          _isProcessing = true;
          final envelope = _mailbox.removeFirst();
          _context._current = this;
          _context._replyTo = envelope.replyTo;
          final result = _actor(_context, envelope.message);
          if (result is Future) {
            await result;
          }
        } catch (error) {
          _actor = _factory(path);
        } finally {
          _isProcessing = false;
          _handleMessage();
        }
      }
    });
  }
}

class Envelope {
  final Object? message;
  final ActorRef? replyTo;

  Envelope(this.message, this.replyTo);
}
