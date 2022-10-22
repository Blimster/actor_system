import 'dart:isolate';

import 'package:actor_system/src/cluster/messages/create_actor.dart';
import 'package:stream_channel/isolate_channel.dart';

class WorkerAdapter {
  final Isolate isolate;
  final IsolateChannel<Object> channel;

  WorkerAdapter(this.isolate, this.channel);

  Future<void> createActor(
    Uri path,
    int? mailboxSize,
    bool useExistingActor,
  ) {
    channel.sink.add(CreateActorRequest(path, mailboxSize, useExistingActor));
    throw UnimplementedError();
  }

  Future<void> stop() async {
    await channel.sink.close();
    await channel.stream.drain();
    isolate.kill();
  }
}
