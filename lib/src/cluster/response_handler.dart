import 'dart:async';

abstract class RequestResponseEnvelope<T> {
  final String type;
  final String correlationId;

  RequestResponseEnvelope(this.type, this.correlationId);

  T get data;
}

abstract class Response<T> {
  String get type;
  String get correlationId;
  T get data;
}

class ResponseHandler<T> {
  final Sink<RequestResponseEnvelope<T>> sink;
  final Map<String, Map<String, _PendingResponse>> handlers = {};

  ResponseHandler(this.sink);

  Future<R> request<R>(
    RequestResponseEnvelope<T> request, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    final handlersForType = handlers.putIfAbsent(request.type, () => {});

    final completer = Completer<R>();
    final timer = Timer(
      timeout,
      () => _handleTimeout(request.type, request.correlationId),
    );
    handlersForType[request.correlationId] = _PendingResponse(completer, timer);

    sink.add(request);

    return completer.future;
  }

  bool applyResponse(String type, String correlationId, Object response) {
    final pendingResponse = _removeResponse(type, correlationId);
    if (pendingResponse == null) {
      return false;
    }
    pendingResponse.timeoutTimer.cancel();
    pendingResponse.completer.complete(response);
    return true;
  }

  void _handleTimeout(String type, String correlationId) {
    final pendingResponse = _removeResponse(type, correlationId);
    if (pendingResponse != null && !pendingResponse.completer.isCompleted) {
      pendingResponse.completer.completeError(TimeoutException(
        'Timeout waiting for response!',
        const Duration(seconds: 5),
      ));
    }
  }

  _PendingResponse? _removeResponse(String type, String correlationId) {
    final responsesForType = handlers[type];
    if (responsesForType != null) {
      final response = responsesForType.remove(correlationId);
      if (responsesForType.isEmpty) {
        handlers.remove(type);
      }
      return response;
    }
    return null;
  }
}

class _PendingResponse {
  final Completer completer;
  final Timer timeoutTimer;

  _PendingResponse(this.completer, this.timeoutTimer);
}
