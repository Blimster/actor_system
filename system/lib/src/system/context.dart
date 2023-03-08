import 'package:actor_system/src/system/actor.dart';
import 'package:actor_system/src/system/base.dart';
import 'package:actor_system/src/system/exceptions.dart';
import 'package:actor_system/src/system/messages.dart';
import 'package:actor_system/src/system/metrics.dart';
import 'package:actor_system/src/system/ref.dart';
import 'package:logging/logging.dart';

/// Defines the handling of an actor path if the host part is missing.
enum MissingHostHandling {
  /// The path is considered to be a path in the local system.
  asLocal,

  /// The path is considered to be an external path. [CreateActor] and
  /// [LookupActor] are used to create and lookup the actor.
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
  final List<MatcherAndFactory> _factories;
  final NullableRef<CreateActor> _externalCreateActor;
  final NullableRef<LookupActor> _externalLookupActor;
  final NullableRef<LookupActors> _externalLookupActors;
  final NullableRef<OnActorAdded> _onActorAdded;
  final NullableRef<OnActorRemoved> _onActorRemoved;
  final MetricsImpl _metrics;
  ActorRef? _current;
  ActorRef? _sender;
  ActorRef? _replyTo;
  String? _correlationId;

  BaseContext._(
    this._name,
    this._missingHostHandling,
    this._actorRefs,
    this._factories,
    this._externalCreateActor,
    this._externalLookupActor,
    this._externalLookupActors,
    this._onActorAdded,
    this._onActorRemoved,
    this._metrics,
  ) : _log = Logger('actor_system.system.BaseContext:$_name');

  /// Creates an actor at the given path.
  ///
  /// The path for an actor must be unique. It is an error to create an actor
  /// with a path, an existing actor already is created with. If the given path
  /// ends with a slash (/), the path is extended by an UUID.
  ///
  /// The given [ActorFactory] is called to create the actor for the given path.
  /// If no factory is provided, a global factory for the given path is
  /// used. If such factory does not exists, an error is thrown. This factory
  /// will also be used to recreate the actor in case of an error.
  ///
  /// If [sendInit] is set to true, the const `initMessage` is sent to the
  /// actors mailbox before the returned future completes.
  Future<ActorRef> createActor(
    Uri path, {
    ActorFactory? factory,
    int? mailboxSize,
    bool sendInit = false,
  }) async {
    path = path.validActorPath();
    _log.info('createActor < path=$path, factory=${factory != null}, mailboxSize=$mailboxSize, sendInit=$sendInit');

    if (!path.hasAbsolutePath) {
      throw ArgumentError.value(path, 'path', 'must be absolute');
    }
    if (path.pathSegments.last.isEmpty) {
      throw ArgumentError.value(path, 'path', 'must not end with a slash');
    }

    if (mailboxSize != null && mailboxSize <= 0) {
      throw ArgumentError.value(mailboxSize, 'mailboxSize', 'must be greater than zero');
    }

    final defaultMailboxSize = 1000;

    /// check if the actor must be created externally
    if (!_isLocalPath(path)) {
      _log.fine('createActor | path is an external path');
      final externalCreate = _externalCreateActor.value;
      if (externalCreate != null) {
        final result = await externalCreate(
          path,
          mailboxSize ?? defaultMailboxSize,
        );
        if (sendInit) {
          await result.send(initMsg);
        }
        _log.fine('createActor > $result');
        return result;
      }
      throw StateError('No external actor create function registered!');
    }

    _log.fine('createActor | path is a local path');
    final existing = _actorRefs[path.path];
    if (existing != null) {
      _log.fine('createActor | found existing actor');
      throw ArgumentError.value(path.path, 'path', 'path already in use');
    }

    // search for registered factory if no factory is provided
    final actorFactory = factory ?? _findFactory(path);
    if (actorFactory == null) {
      throw NoFactoryFound(path);
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
        _externalCreateActor,
        _externalLookupActor,
        _externalLookupActors,
        _onActorAdded,
        _onActorRemoved,
        _metrics,
      ),
      _onMessageProcessed,
      _onActorStopped,
    );
    if (_isLocalPath(path)) {
      _actorRefs[actorPath.path] = actorRef;
      _onActorAdded.value?.call(actorRef.path);
    }

    if (sendInit) {
      await actorRef.send(initMsg);
    }

    _log.info('createActor > $actorRef');
    return actorRef;
  }

  /// Looks up an actor reference using the given path. If no actor exists for
  /// that path, null is returned.
  Future<ActorRef?> lookupActor(Uri path) async {
    path = path.validActorPath();
    _log.info('lookupActor < path=$path');

    if (!path.hasAbsolutePath) {
      throw ArgumentError.value(path, 'path', 'must be absolute');
    }
    if (path.pathSegments.last.isEmpty) {
      throw ArgumentError.value(path, 'path', 'must not end with a slash');
    }

    if (_isLocalPath(path)) {
      _log.info('lookupActor | path is a local path');
      final result = _actorRefs[path.path];
      _log.info('lookupActor > $result');
      return result;
    }
    final result = await _externalLookupActor.value?.call(path);
    _log.info('lookupActor > $result');
    return result;
  }

  Future<List<ActorRef>> lookupActors(Uri path) async {
    path = path.validActorPath();
    _log.info('lookupActors < path=$path');

    if (!path.hasAbsolutePath) {
      throw ArgumentError.value(path, 'path', 'must be absolute');
    }

    final result = <ActorRef>[];
    if (_isLocalPath(path)) {
      _log.info('lookupActors | path is a local path');

      for (final actorRef in _actorRefs.entries) {
        if (actorRef.key.startsWith(path.path)) {
          result.add(actorRef.value);
        }
      }
    } else {
      _log.info('lookupActors | path is an external path');
      final externalActors = await _externalLookupActors.value?.call(path);
      if (externalActors != null) {
        result.addAll(externalActors);
      }
    }
    _log.info('lookupActors > $result');
    return result;
  }

  ActorFactory? _findFactory(Uri path) {
    _log.fine('_findFactory < path=$path');
    for (final factory in _factories) {
      if (factory.matcher(path)) {
        _log.fine('_findFactory | factory found');
        _log.fine('_findFactory > ActorFactory');
        return factory.factory;
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
    return actorPath(path.path, system: path.host.isNotEmpty ? path.host : _name);
  }

  void _onMessageProcessed(Uri path, int processingTimeMs, int mailBoxLength) {
    _metrics.update(path, processingTimeMs, mailBoxLength);
  }

  void _onActorStopped(String path) {
    final ref = _actorRefs.remove(path);
    if (ref != null) {
      _onActorRemoved.value?.call(ref.path);
    }
  }
}

/// A context for an actor. The context is provided to the actor for
class ActorContext extends BaseContext {
  ActorContext._(
    String name,
    MissingHostHandling missingHostHandling,
    Map<String, ActorRef> actorRefs,
    List<MatcherAndFactory> factories,
    NullableRef<CreateActor> externalCreate,
    NullableRef<LookupActor> externalLookup,
    NullableRef<LookupActors> externalLookups,
    NullableRef<OnActorAdded> onActorAdded,
    NullableRef<OnActorRemoved> onActorRemoved,
    MetricsImpl metrics,
  ) : super._(
          name,
          missingHostHandling,
          actorRefs,
          factories,
          externalCreate,
          externalLookup,
          externalLookups,
          onActorAdded,
          onActorRemoved,
          metrics,
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

/// Return a [PathMatcher] that uses the given [pattern] on the path
/// of the actor.
PathMatcher patternMatcher(Pattern pattern) {
  return (Uri path) {
    final matches = pattern.allMatches(path.path);
    return matches.isNotEmpty;
  };
}

/// Returns true, if the given path matches.
typedef PathMatcher = bool Function(Uri path);

/// An [ActorSystem] is a collection of actors, the can communicate with each
/// other. An actor can only create or lookup actors in the same [ActorSystem].
class ActorSystem extends BaseContext {
  /// Creates a new [ActorSystem].
  ActorSystem({String name = localSystem, MissingHostHandling missingHostHandling = MissingHostHandling.asLocal})
      : super._(
          name.toLowerCase(),
          missingHostHandling,
          {},
          [],
          NullableRef(),
          NullableRef(),
          NullableRef(),
          NullableRef(),
          NullableRef(),
          MetricsImpl(),
        );

  /// The metrics for this actor system.
  ActorSystemMetrics get metrics => _metrics;

  /// The paths of all actors in this system.
  List<Uri> get actorPaths => _actorRefs.values.map((e) => e.path).toList()..sort((a, b) => a.path.compareTo(b.path));

  /// Adds a global actor factory for the actor system. A global factory is used
  /// to create a new actor if the caller of [BaseContext.createActor] provides no
  /// factory. The first factory (in order they were added) where the matcher
  /// returns true is called to create the actor. If no matcher matches, an
  /// exception is thrown.
  void addActorFactory(PathMatcher pathMatcher, ActorFactory factory) {
    _factories.add(MatcherAndFactory(pathMatcher, factory));
  }

  /// Sets the external create create function. This function is used to create actors
  /// outside of the current [ActorSystem].
  set externalCreateActor(CreateActor? create) => _externalCreateActor.value = create;

  /// Sets the external lookup actor function. This function is used to lookup an actor
  /// outside of the current [ActorSystem].
  set externalLookupActor(LookupActor? lookup) => _externalLookupActor.value = lookup;

  /// Sets the external lookup actors function. This function is used to lookup a actors
  /// outside of the current [ActorSystem].
  set externalLookupActors(LookupActors? lookup) => _externalLookupActors.value = lookup;

  /// Sets a callback function that is called when an actor is added to the system.
  set onActorAdded(OnActorAdded? onActorAdded) => _onActorAdded.value = onActorAdded;

  /// Sets a callback function that is called when an actor is removed from the system.
  set onActorRemoved(OnActorRemoved? onActorRemoved) => _onActorRemoved.value = onActorRemoved;
}

class MatcherAndFactory {
  final PathMatcher matcher;
  final ActorFactory factory;
  MatcherAndFactory(this.matcher, this.factory);
}
