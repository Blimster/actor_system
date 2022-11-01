class CreateActorRequest {
  final Uri path;
  final int? mailboxSize;
  final bool? useExistingActor;

  CreateActorRequest(this.path, this.mailboxSize, this.useExistingActor);

  @override
  String toString() => 'CreateActorRequest(path=$path, mailboxSize=$mailboxSize, useExistingActor=$useExistingActor)';
}

class CreateActorResponse {
  final bool success;
  final String message;

  CreateActorResponse(this.success, this.message);

  @override
  String toString() => 'CreateActorResponse(success=$success, message=$message)';
}
