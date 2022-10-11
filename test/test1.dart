import 'package:actor_system/actor_cluster.dart';
import 'package:actor_system/src/base/string_extension.dart';
import 'package:logging/logging.dart';

void main() async {
  Logger.root.level = Level.ALL;
  Logger.root.onRecord.listen((record) {
    print(
        '[${record.time.toString().padRight(26, '0')}|${record.level.name.padLeft(7, ' ')}|${record.loggerName.abbreviate(20).padLeft(20)}] ${record.message}');
  });

  final node = await SystemNode('config1')
    ..init();

  final state = node.state;
  if (state == NodeState.started) {
    print('Node is running');
  }
}
