import 'dart:async';

import 'package:actor_system/actor_system.dart';

class ActorRefProxy implements ActorRef {
  final Uri _path;
  final Future<void> Function(
    Uri path,
    Object? message,
    Uri? sender,
    Uri? replyTo,
    String? correlationId,
  ) _send;

  ActorRefProxy(this._path, this._send);

  @override
  Uri get path => _path;

  @override
  Future<void> send(Object? message, {ActorRef? replyTo, String? correlationId}) {
    final sender = Zone.current[zoneSenderKey] as ActorRef?;
    return _send(_path, message, sender?.path, replyTo?.path, correlationId);
  }

  @override
  Future<void> shutdown() => send(shutdownMsg);

  @override
  String toString() => 'ActorRefProxy(path=$path)';
}
