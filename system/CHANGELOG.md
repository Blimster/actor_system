# Changelog

## 0.9.2

- Bugfix: `sender` and `correlationId` from current context was determined in the wrong point of time. Thus, wrong values could be return from `ActorContext.sender` and `ActorContext.correlationId`.

## 0.9.1

- Bugfix: "one message at a time" was not fulfilled for async message processing.

## 0.9.0

- BREAKING CHANGE: if the `correlationId` is not explicitly set as parameter of `ActorRef.send()` it is implicitly set set from the context of the current actor (if available).

## 0.8.1

- The key `zoneSenderKey` to set or get an actor as the sender in the current `Zone` is now public.

## 0.8.0

- BREAKING CHANGE: it is no longer possible to exclitly specifying a sender, when sending a message to an actor. Instead, it is implcitly set, if the message was sent in the context of an actor.

## 0.7.2

- It is now possible to set callback function to be callled when an actors is added or removed from a system by using the setters `ActorSystem.onActorAdded` and `ActorSystem.onActorRemoved`.

## 0.7.1

- It is now possible to get metrics of an actor system by using `ActorSystem.metrics`.
- It is now possbile to get a list of all available actor paths by using `ActorSystem.actorPaths`.
^
## 0.7.0

- BREAKING CHANGE: parameter `path` of `lookupActor()` and `lookupActors()` must be absolute.
- BREAKING CHANGE: parameter `path` of `createActor()` and `lookupActor()` must not end with a slash.
- Bugfix: it was possible to create more than one actor on the same path.
- Improved handling of an empty fragment in `validActorPath()` and `copyWith()` of `UriExtension`.

## 0.6.0

- BREAKING CHANGE: renamed `UriExtension.copy()` to `UriExtension.copy()` and renamed parameter `fragment` to `tag`.
- Added named parameter `tag` to `actorPath()`.

## 0.5.1

- Added helper to copy an Uri.

## 0.5.0

- BREAKING CHANGE: renamed `ExternalActorCreate` to `CreateActor`.
- BREAKING CHANGE: renamed `ExternalActorLookup` to `LookupActor`.
- BREAKING CHANGE: renamed `ActorSyste.externalCreate` to `ActorSyste.externalCreateActor`.
- BREAKING CHANGE: renamed `ActorSyste.externalLookup` to `ActorSyste.externalLlookupActor`.
- Added `BaseContext.lookupActors()`

## 0.4.0

- BREAKING CHANGE: moved cluster functionality to an separate package.
- BREAKING CHANGE: renamed library `actor_builder` to `actor_system_helper`.
- BREAKING CHANGE: reaname class `WhenLikeActorBuilder` to `ActorBuilder`.
- BREAKING CHANGE: class `ActorBuilder` no longer has a method `actor()`. Use `orActor()`, `orSkip()` or `orThrow()` instead.
- BREAKING CHANGE: replaced `ActorSystem.registerFactory(Pattern, ActorFactory)` by `ActorSystem.addActorFactory(PathMatcher, ActoryFactory)`.
- It is now possible to stop an actor. This can be done by calling `ActorRef.shutdown()` or sending the constant `shutdownMsg` to the actor.
- An actor can now throw a `SkipMessage` while executing a message. In contrast to all other exceptions thrown by an actor, the actor is not restarted.
- Added `ActorContextExtension` on `ActorContext` with getters `senderOrSkip`, `replyToOrSkip` and `correlationIdOrSkip`. Use these methods to get null safe versions of `sender`,  `replyTo` and `correlationId`. If a value is `null`, a `SkipMessage` is thrown.

## 0.3.0

- BREAKING CHANGE: removed parameter `useExistingActor` from `BaseContext.createActor()`.
- `BaseContext.createActor()` has a new parameter `sendInit`. If set to `true`, an `initMsg` is sent after the actor is created.
- `ActorRef.send()` now has a new parameter `correlationId`. An actor can read the correlation id from its context.
- `WhenLikeActorBuilder` has new methods `isTrue()` and `isInit()`.

## 0.2.2

- `ActorRef.send()` now has a new parameter `sender`.

## 0.2.1

- Prefixed all logger names in library `actor_system` with `actor_system.system.` and all logger names in library `actor_cluster` with `actor_system.cluster.`.
## 0.2.0

- Improved package score on pub.dev
- More useful version of README.md
- BREAKING CHANGE: Refactored `WhenLikeActorBuilder.equals(Object?, Actor)` to `WhenLikeActorBuilder.isEqual<T>(T, FutureOr<void> Function(ActorContext, T))`

## 0.1.1

- Changed dependency from `msgpack_dart` to `msgpack_dart_with_web` to support web

## 0.1.0

- Initial release