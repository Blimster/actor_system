import 'package:actor_system/src/system/ref.dart';

class ActorRefProxy implements ActorRef {
  final Uri _path;
  final Future<void> Function(
    Uri path,
    Object? message,
    Uri? replyTo,
  ) _send;

  ActorRefProxy(this._path, this._send);

  @override
  Uri get path => _path;

  @override
  Future<void> send(Object? message, {ActorRef? replyTo}) {
    return _send(_path, message, replyTo?.path);
  }

  @override
  String toString() => 'ActorRefProxy(path=$path)';
}
