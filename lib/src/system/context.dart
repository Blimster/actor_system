import 'package:actor_system/src/base/reference.dart';
import 'package:actor_system/src/base/uri.dart';
import 'package:actor_system/src/system/actor.dart';
import 'package:actor_system/src/system/ref.dart';
import 'package:logging/logging.dart';
import 'package:uuid/uuid.dart';

/// Defines the handling of an actor path if the host part is missing.
enum MissingHostHandling {
  /// The path is considered to be a path in the local system.
  asLocal,

  /// The path is considered to be an external path. [ExternalActorCreate] and
  /// [ExternalActorLookup] are used to create and lookup the actor.
  asExternal,
}

void prepareContext(
  ActorContext context,
  ActorRef current,
  ActorRef? sender,
  ActorRef? replyTo,
  String? correlationId,
) {
  context._current = current;
  context._sender = sender;
  context._replyTo = replyTo;
  context._correlationId = correlationId;
}

abstract class BaseContext {
  final Logger _log;
  final String _name;
  final MissingHostHandling _missingHostHandling;
  final Map<String, ActorRef> _actorRefs;
  final Map<Pattern, ActorFactory> _factories;
  final NullableRef<ExternalActorCreate> _externalCreate;
  final NullableRef<ExternalActorLookup> _externalLookup;
  ActorRef? _current;
  ActorRef? _sender;
  ActorRef? _replyTo;
  String? _correlationId;

  BaseContext._(
    this._name,
    this._missingHostHandling,
    this._actorRefs,
    this._factories,
    this._externalCreate,
    this._externalLookup,
  ) : _log = Logger('actor_system.system.BaseContext:$_name');

  /// Creates an actor at the given path.
  ///
  /// The path for an actor must be unique. It is an error to create an actor
  /// with a path, an existing actor already is created with. If the given path
  /// ends with a slash (/), the path is extended by an UUID.
  ///
  /// The given [ActorFactory] is called to create the actor for the given path.
  /// If no factory is provided, a registered factory for the given path is
  /// used. If such factory does not exists, an error is thrown. This factory
  /// will also be used to recreate the actor in case of an error.
  ///
  /// If [useExistingActor] is set to true, the provided path ends not with a
  /// slash and an actor with the path already exists, the existing actor is
  /// returned instead a newly created actor.
  ///
  /// If [useExistingActor] is set to false and there is already an actor with
  /// the given path, an error is thrown.
  Future<ActorRef> createActor(
    Uri path, {
    ActorFactory? factory,
    int? mailboxSize,
    bool? useExistingActor,
  }) async {
    _log.info(
        'createActor < path=$path, factory=${factory != null}, mailboxSize=$mailboxSize, useExistingActor=$useExistingActor');

    if (!path.hasAbsolutePath) {
      throw ArgumentError.value(path, 'path', 'must be an absolte uri!');
    }
    if (mailboxSize != null && mailboxSize <= 0) {
      throw ArgumentError.value(mailboxSize, 'mailboxSize', 'must be greater than zero!');
    }

    final defaultMailboxSize = 1000;
    final defaultUseExisting = false;

    /// check if the actor must be created externally
    if (!_isLocalPath(path)) {
      _log.fine('createActor | path is an external path');
      final externalCreate = _externalCreate.value;
      if (externalCreate != null) {
        final result = externalCreate(path, mailboxSize ?? defaultMailboxSize, useExistingActor ?? defaultUseExisting);
        _log.fine('createActor > $result');
        return result;
      }
      throw StateError('No external actor create function registered!');
    }
    _log.fine('createActor | path is a local path');

    if (path.pathSegments.last.isNotEmpty) {
      // path does not end with a slash (/). is the path already in use?
      final existing = _actorRefs[path];
      if (existing != null) {
        _log.fine('createActor | found existing actor');
        if (useExistingActor ?? defaultUseExisting) {
          _log.fine('createActor > $existing');
          return existing;
        } else {
          throw ArgumentError.value(path.path, 'path', 'path already in use!');
        }
      }
    }

    // search for registered factory if no factory is provided
    final actorFactory = factory ?? _findFactory(path.path);
    if (actorFactory == null) {
      throw ArgumentError.value(path.path, 'path', 'no factory for path!');
    }

    // create, store and return the actor ref
    final actorPath = _finalActorPath(path);
    _log.fine('createActor | final path is $actorPath');
    final actorRef = createActorRef(
        actorPath,
        mailboxSize ?? defaultMailboxSize,
        await actorFactory(actorPath),
        actorFactory,
        ActorContext._(
          _name,
          _missingHostHandling,
          _actorRefs,
          _factories,
          _externalCreate,
          _externalLookup,
        ));
    if (_isLocalPath(path)) {
      _actorRefs[actorPath.path] = actorRef;
    }

    _log.info('createActor > $actorRef');
    return actorRef;
  }

  /// Looks up an actor reference using the given path. If no actor exists for
  /// that path, null is returned.
  Future<ActorRef?> lookupActor(Uri path) async {
    _log.info('lookupActor < path=$path');
    if (_isLocalPath(path)) {
      _log.info('lookupActor | path is a local path');
      final result = _actorRefs[path.path];
      _log.info('lookupActor > $result');
      return result;
    }
    final result = await _externalLookup.value?.call(path);
    _log.info('lookupActor > $result');
    return result;
  }

  ActorFactory? _findFactory(String path) {
    _log.fine('_findFactory < path=$path');
    for (final entry in _factories.entries) {
      final matches = entry.key.allMatches(path);
      if (matches.isNotEmpty) {
        _log.fine('_findFactory | factory found with pattern ${entry.key}');
        _log.fine('_findFactory > ActorFactory');
        return entry.value;
      }
    }
    _log.fine('_findFactory > null');
    return null;
  }

  bool _isLocalPath(Uri path) {
    if (path.host.isEmpty) {
      return _missingHostHandling == MissingHostHandling.asLocal;
    }
    return path.host == localSystem || path.host.toLowerCase() == _name;
  }

  Uri _finalActorPath(Uri path) {
    if (path.pathSegments.last.isNotEmpty) {
      return actorPath(path.path, system: path.host.isNotEmpty ? path.host : _name);
    } else {
      var result = actorPath(path.resolve(Uuid().v4()).path, system: _name);
      while (_actorRefs.keys.contains(result.path)) {
        result = path.resolve(Uuid().v4());
      }
      return result;
    }
  }
}

/// A context for an actor. The context is provided to the actor for
class ActorContext extends BaseContext {
  ActorContext._(
    String name,
    MissingHostHandling missingHostHandling,
    Map<String, ActorRef> actorRefs,
    Map<Pattern, ActorFactory> factories,
    NullableRef<ExternalActorCreate> externalCreate,
    NullableRef<ExternalActorLookup> externalLookup,
  ) : super._(
          name,
          missingHostHandling,
          actorRefs,
          factories,
          externalCreate,
          externalLookup,
        );

  /// The current reference.
  ActorRef get current {
    final current = _current;
    if (current != null) {
      return current;
    }
    throw StateError('No current actor reference!');
  }

  /// The reference to the sender of the message.
  ActorRef? get sender => _sender;

  /// The reference to the actor to reply to.
  ActorRef? get replyTo => _replyTo;

  /// The correlation id for this current message.
  String? get correlationId => _correlationId;
}

/// An [ActorSystem] is a collection of actors, the can communicate with each
/// other. An actor can only create or lookup actors in the same [ActorSystem].
class ActorSystem extends BaseContext {
  /// Creates a new [ActorSystem].
  ActorSystem({String name = localSystem, MissingHostHandling missingHostHandling = MissingHostHandling.asLocal})
      : super._(
          name.toLowerCase(),
          missingHostHandling,
          {},
          {},
          NullableRef(),
          NullableRef(),
        );

  /// Registers an [ActorFactory] for the given [path]. The factory is used to
  /// create a new actor if a call to [ActorContext.createActor] has no factory
  /// and the path matches.
  void registerFactory(Pattern pattern, ActorFactory factory) {
    _factories[pattern] = factory;
  }

  /// Sets the external create function. This function is used to create actors
  /// outside of the current [ActorSystem].
  set externalCreate(ExternalActorCreate? create) => _externalCreate.value = create;

  /// Sets the external lookup function. This function is used to lookup actors
  /// outside of the current [ActorSystem].
  set externalLookup(ExternalActorLookup? lookup) => _externalLookup.value = lookup;
}
