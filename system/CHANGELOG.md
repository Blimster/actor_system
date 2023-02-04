# Changelog

## 0.4.0

- BREAKING CHANGE: moved cluster functionality to an separate package.
- BREAKING CHANGE: renamed library `actor_builder` to `actor_system_helper`.
- BREAKING CHANGE: reaname class `WhenLikeActorBuilder` to `ActorBuilder`.
- BREAKING CHANGE: class `ActorBuilder` no longer has a method `actor()`. Use `orActor()`, `orSkip()` or `orThrow()` instead.
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