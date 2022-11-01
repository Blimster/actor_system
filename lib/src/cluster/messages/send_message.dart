class SendMessageRequest {
  final Uri path;
  final Object? message;
  final Uri? replyTo;

  SendMessageRequest(this.path, this.message, this.replyTo);
}

class SendMessageResponse {
  final bool success;
  final String message;

  SendMessageResponse(this.success, this.message);
}
