import 'dart:io';

import 'package:yaml/yaml.dart';

class ConfigNode {
  final String host;
  final int port;
  final String id;

  ConfigNode(this.host, this.port, this.id);

  @override
  String toString() => 'adress=$host:$port, id=$id';
}

class ClusterConfig {
  final List<ConfigNode> nodes;
  final Map<String, int> tags;
  final int timeout;
  final String secret;

  ClusterConfig(
    this.nodes,
    this.tags,
    this.timeout,
    this.secret,
  );
}

class NodeConfig {
  final ConfigNode node;
  final int workers;
  final List<String> tags;

  NodeConfig(this.node, this.workers, this.tags);
}

Future<ClusterConfig> readClusterConfigFromYaml(String filename, {List<String>? keyHierarchy}) async {
  final yaml = await File(filename).readAsString();
  final YamlMap config = loadYaml(yaml);

  var rootNode = config;
  for (final key in keyHierarchy ?? []) {
    final node = rootNode[key];
    if (node is YamlMap) {
      rootNode = node;
    } else {
      print(node);
      throw ArgumentError('key hierarchy ${(keyHierarchy ?? []).join('.')} is not valid');
    }
  }

  final tags = <String, int>{};
  if (rootNode['tags'] != null) {
    for (final tag in rootNode['tags'].entries) {
      tags[tag.key] = tag.value;
    }
  }

  return ClusterConfig(
    (rootNode['nodes'] as YamlList).map((e) => ConfigNode(e['host'], e['port'], e['id'])).toList(),
    tags,
    rootNode['timeout'],
    rootNode['secret'],
  );
}

Future<NodeConfig> readNodeConfigFromYaml(String filename, {List<String>? keyHierarchy}) async {
  final yaml = await File(filename).readAsString();
  final YamlMap config = loadYaml(yaml);

  var rootNode = config;
  for (final key in keyHierarchy ?? []) {
    final node = rootNode[key];
    if (node is YamlMap) {
      rootNode = node;
    } else {
      print(node);
      throw ArgumentError('key hierarchy ${(keyHierarchy ?? []).join('.')} is not valid');
    }
  }

  final tags = <String>[];
  if (rootNode['tags'] != null) {
    for (final tag in rootNode['tags']) {
      tags.add(tag);
    }
  }

  return NodeConfig(
    ConfigNode(
      rootNode['node']['host'],
      rootNode['node']['port'],
      rootNode['node']['id'],
    ),
    rootNode['workers'],
    tags,
  );
}
