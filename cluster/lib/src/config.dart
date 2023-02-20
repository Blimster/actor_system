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

Future<ClusterConfig> readClusterConfigFromYaml(String filename) async {
  final yaml = await File(filename).readAsString();
  final YamlMap config = loadYaml(yaml);

  final tags = <String, int>{};
  if (config['tags'] != null) {
    for (final tag in config['tags'].entries) {
      tags[tag.key] = tag.value;
    }
  }

  return ClusterConfig(
    (config['nodes'] as YamlList).map((e) => ConfigNode(e['host'], e['port'], e['id'])).toList(),
    tags,
    config['timeout'],
    config['secret'],
  );
}

Future<NodeConfig> readNodeConfigFromYaml(String filename) async {
  final yaml = await File(filename).readAsString();
  final YamlMap config = loadYaml(yaml);

  final tags = <String>[];
  if (config['tags'] != null) {
    for (final tag in config['tags']) {
      tags.add(tag);
    }
  }

  return NodeConfig(
    ConfigNode(
      config['node']['host'],
      config['node']['port'],
      config['node']['id'],
    ),
    config['workers'],
    tags,
  );
}
