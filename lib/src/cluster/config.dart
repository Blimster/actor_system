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
  final String logLevel;

  Config(
    this.seedNodes,
    this.localNode,
    this.workers,
    this.secret,
    this.logLevel,
  );
}
