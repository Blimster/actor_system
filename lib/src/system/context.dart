import 'package:actor_system/src/base/reference.dart';
import 'package:actor_system/src/base/uri.dart';
import 'package:actor_system/src/system/actor.dart';
import 'package:actor_system/src/system/ref.dart';

void prepareContext(
  ActorContext context,
  ActorRef current,
  ActorRef? replyTo,
) {
  context._current = current;
  context._replyTo = replyTo;
}

abstract class BaseContext {
  final String? _name;
  final Map<String, ActorRef> _actorRefs;
  final Map<String, ActorFactory> _factories;
  NullableRef<ExternalActorCreate> _externalCreate;
  NullableRef<ExternalActorLookup> _externalLookup;
  ActorRef? _current;
  ActorRef? _replyTo;

  BaseContext(
    this._name,
    this._actorRefs,
    this._factories,
    this._externalCreate,
    this._externalLookup,
  );

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
    bool useExistingActor = false,
  }) async {
    if (!path.hasAbsolutePath) {
      throw ArgumentError.value(path, 'path', 'must be an absolte uri!');
    }
    if (mailboxSize != null && mailboxSize <= 0) {
      throw ArgumentError.value(
          mailboxSize, 'mailboxSize', 'must be greater than zero!');
    }

    if (path.host.isNotEmpty && path.host != _name) {
      final externalFactory = _externalCreate.value;
      if (externalFactory != null) {
        return externalFactory(path);
      }
      throw StateError('No external actor create function registered!');
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
    final actorFactory = factory ?? _factories[path.path];
    if (actorFactory == null) {
      throw ArgumentError.value(path.path, 'path', 'no factory for path!');
    }

    // create, store and return the actor ref
    final actorPath = path.completeActorPath(_actorRefs.keys);
    final actorRef = createActorRef(
        actorPath,
        mailboxSize ?? 1000,
        await actorFactory(actorPath),
        actorFactory,
        ActorContext._(
          _name,
          _actorRefs,
          _factories,
          _externalCreate,
          _externalLookup,
        ));
    _actorRefs[actorPath.path] = actorRef;

    return actorRef;
  }

  /// Looks up an actor reference using the given path. If no actor exists for
  /// that path, null is returned.
  Future<ActorRef?> lookupActor(Uri path) async {
    if (path.host.isEmpty || path.host == _name) {
      return _actorRefs[path.path];
    }
    return _externalLookup.value?.call(path);
  }
}

/// A context for an actor. The context is provided to the actor for
class ActorContext extends BaseContext {
  ActorContext._(
    super.name,
    super._actorRefs,
    super._factories,
    super._externalCreate,
    super._externalLookup,
  );

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
}

/// An [ActorSystem] is a collection of actors, the can communicate with each
/// other. An actor can only create or lookup actors in the same [ActorSystem].
class ActorSystem extends BaseContext {
  /// Creates a new [ActorSystem].
  ActorSystem({String? name})
      : super(
          name,
          {},
          {},
          NullableRef(),
          NullableRef(),
        );

  /// Registers an [ActorFactory] for the given [path]. The factory is used to
  /// create a new actor if a call to [ActorContext.createActor] has no factory
  /// and the path matches.
  void registerFactory(Uri path, ActorFactory factory) {
    _factories[path.path] = factory;
  }

  /// Sets the external create function. This function is used to create actors
  /// outside of the current [ActorSystem].
  set externalCreate(ExternalActorCreate? create) =>
      _externalCreate.value = create;

  /// Sets the external lookup function. This function is used to lookup actors
  /// outside of the current [ActorSystem].
  set externalLookup(ExternalActorLookup? lookup) =>
      _externalLookup.value = lookup;
}
