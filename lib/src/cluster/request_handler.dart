import 'dart:async';

class RequestHandler {
  final Map<String, dynamic> handlers = {};

  void onRequest<T>(String type, FutureOr<Object> Function(T request) handler) {
    handlers[type] = handler;
  }

  Future<R?> handleRequest<R>(String type, R request) async {
    final handler = handlers[type];
    if (handler != null) {
      return await handler(request) as R;
    }
    return null;
  }
}
