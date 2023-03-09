# Changelog

## 0.2.0

- BREAKING CHANGE: based on version 0.7.2 of package `actor_system`.
- BREAKING CHANGE: Splitted configuration into separate parts for cluster and node.
- Node selection for actors to be created is now based on node metrics.
- Cluster nodes can be configured with tags. For each tag the number of required nodes can be configured. If configured, the cluster will only start, if all required tags are available.
- The `path` parameter of `createActor()` can now contain a fragment. The fragment is used as a node tag. The actor will be created on a node tagged with the given tag.

## 0.1.0

- Based on library `actor_cluster` of version `0.3.0` of package `actor_system`.
- BREAKING CHANGE: Renamed `PrepareNodeSystem` to `AddActorFactories`.
- BREAKING CHANGE: Renamed parameter `prepareNodeSystem` of `ActorCluster.init()` to `addActorFactories`.
- BREAKING CHANGE: Renamed parameter `afterClusterInit` of `ActorCluster.init()` to `initCluster`.
- BREAKING CHANGE: `initCluster` is now only called on leader node.
