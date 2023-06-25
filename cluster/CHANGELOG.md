# Changelog

## 0.4.3

- Removed unintentional ```print()``` call.

## 0.4.2

- `readClusterConfigFromYaml()` and `readNodeConfigFromYaml()` now have an additional parameter `keyHierarchy` to read the config from a subnode.

## 0.4.1

- Bugfix: node selection based on load could lead to select no node.

## 0.4.0

- BREAKING CHANGE: based on version 0.8.1 of package `actor_system`.

## 0.3.0

- Removed parameter `onLogRecord` from the constructor of `ActorCluster`. Use the new parameter `initWorkerIsolate` instead.
- Added parameter `initWorkerIsolate` to the constructor of `ActorCluster`. Use this callback to initialize the isolate of a worker.

## 0.2.2

- Library `actor_system_helper` is exported by this library.

## 0.2.1

- Library `actor_system` is exported by this library.

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
