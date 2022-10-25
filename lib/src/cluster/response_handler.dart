import 'dart:async';

class _PendingResponse {
  final Completer completer;
  final Timer timeoutTimer;

  _PendingResponse(this.completer, this.timeoutTimer);
}

class ResponseHandler {
  final Map<String, Map<String, _PendingResponse>> handlers = {};

  Future<R> waitForResponse<R>(
    String type,
    String correlationId, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    final handlersForType = handlers.putIfAbsent(type, () => {});

    final completer = Completer<R>();
    final timer = Timer(timeout, () => _handleTimeout(type, correlationId));
    handlersForType[correlationId] = _PendingResponse(completer, timer);

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
