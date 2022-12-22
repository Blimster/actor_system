# Changelog

## 0.2.0

- Improved package score on pub.dev
- More useful version of README.md
- BREAKING CHANGE: Refactored `WhenLikeActorBuilder.equals(Object?, Actor)` to `WhenLikeActorBuilder.isEqual<T>(T, FutureOr<void> Function(ActorContext, T))`

## 0.1.1

- Changed dependency from `msgpack_dart` to `msgpack_dart_with_web` to support web

## 0.1.0

- Initial release