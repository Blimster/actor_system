import 'dart:isolate';

import 'package:actor_system/src/base/uri.dart';
import 'package:actor_system/src/cluster/messages/create_actor.dart';
import 'package:actor_system/src/cluster/response_handler.dart';
import 'package:actor_system/src/system/ref.dart';
import 'package:stream_channel/isolate_channel.dart';

class IsolateMessage {
  final String type;
  final String correlationId;
  final Object content;

  IsolateMessage(this.type, this.correlationId, this.content);
}

class IsolateAdapter {
  final String nodeId;
  final int workerId;
  final ResponseHandler requestResponseHandler = ResponseHandler();
  final Isolate isolate;
  final IsolateChannel<IsolateMessage> channel;

  IsolateAdapter(this.nodeId, this.workerId, this.isolate, this.channel) {
    channel.stream.listen((message) async {
      final wasResponse = await requestResponseHandler.applyResponse(
        message.type,
        message.correlationId,
        message.content,
      );
      if (!wasResponse) {
        throw UnimplementedError('only response are supported at the moment');
      }
    });
  }

  Future<ActorRef> createActor(
    Uri path,
    int? mailboxSize,
    bool useExistingActor,
  ) async {
    final message = createActorRequest(path, mailboxSize, useExistingActor);
    channel.sink.add(message);

    final response =
        await requestResponseHandler.waitForResponse<CreateActorResponse>(
      message.type,
      message.correlationId,
    );

    if (!response.success) {
      throw Exception(response.message);
    }
    return _WorkerActorRef(Uri(
      scheme: actorScheme,
      host: nodeId,
      port: workerId,
      path: response.message,
    ));
  }

  Future<void> stop() async {
    await channel.sink.close();
    isolate.kill();
  }
}

class _WorkerActorRef implements ActorRef {
  final Uri _path;

  _WorkerActorRef(this._path);

  @override
  Uri get path => _path;

  @override
  Future<void> send(Object? message, {ActorRef? replyTo}) {
    throw UnimplementedError();
  }
}
