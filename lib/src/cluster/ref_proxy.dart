import 'package:actor_system/src/system/ref.dart';

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
  Future<void> send(Object? message, {ActorRef? sender, ActorRef? replyTo, String? correlationId}) {
    return _send(_path, message, sender?.path, replyTo?.path, correlationId);
  }

  @override
  String toString() => 'ActorRefProxy(path=$path)';
}
