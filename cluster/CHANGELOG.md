# Changelog

## 0.2.0

- BREAKING CHANGE: based on version 0.6.0 of package `actor_system`.
- BREAKING CHANGE: Splitted configuration into separate parts for cluster and node.
- Cluster nodes can be configured with tags and for each tag the number of required nodes can be configured. If configured, the cluster will only start, if all required tags are available.

## 0.1.0

- Based on library `actor_cluster` of version `0.3.0` of package `actor_system`.
- BREAKING CHANGE: Renamed `PrepareNodeSystem` to `AddActorFactories`.
- BREAKING CHANGE: Renamed parameter `prepareNodeSystem` of `ActorCluster.init()` to `addActorFactories`.
- BREAKING CHANGE: Renamed parameter `afterClusterInit` of `ActorCluster.init()` to `initCluster`.
- BREAKING CHANGE: `initCluster` is now only called on leader node.
