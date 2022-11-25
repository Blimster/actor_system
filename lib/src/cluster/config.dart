import 'dart:io';

import 'package:yaml/yaml.dart';

class ConfigNode {
  final String host;
  final int port;
  final String id;

  ConfigNode(this.host, this.port, this.id);

  String toString() => 'adress=$host:$port, id=$id';
}

class Config {
  final List<ConfigNode> seedNodes;
  final ConfigNode localNode;
  final int workers;
  final String secret;
  final int timeout;

  Config(
    this.seedNodes,
    this.localNode,
    this.workers,
    this.secret,
    this.timeout,
  );
}

Future<Config> readConfigFromYaml(String filename) async {
  final yaml = await File('$filename').readAsString();
  final YamlMap config = loadYaml(yaml);

  return Config(
    (config['seedNodes'] as YamlList).map((e) => ConfigNode(e['host'], e['port'], e['id'])).toList(),
    ConfigNode(
      config['localNode']['host'],
      config['localNode']['port'],
      config['localNode']['id'],
    ),
    config['workers'],
    config['secret'],
    config['timeout'],
  );
}
