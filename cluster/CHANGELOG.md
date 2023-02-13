# Changelog

## 0.2.0

- BREAKING CHANGE: based on version 0.5.0 of package `actor_system`.

## 0.1.0

- Based on library `actor_cluster` of version `0.3.0` of package `actor_system`.
- BREAKING CHANGE: Renamed `PrepareNodeSystem` to `AddActorFactories`.
- BREAKING CHANGE: Renamed parameter `prepareNodeSystem` of `ActorCluster.init()` to `addActorFactories`.
- BREAKING CHANGE: Renamed parameter `afterClusterInit` of `ActorCluster.init()` to `initCluster`.
- BREAKING CHANGE: `initCluster` is now only called on leader node.
