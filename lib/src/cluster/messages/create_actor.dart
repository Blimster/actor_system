import 'package:actor_system/src/cluster/worker_adapter.dart';
import 'package:uuid/uuid.dart';

const createActorRequestType = 'CREATE_ACTOR_REQ';
const createActorResponseType = 'CREATE_ACTOR_RES';

IsolateMessage createActorRequest(
  Uri path,
  int? mailboxSize,
  bool useExistingActor,
) {
  return IsolateMessage(
    createActorRequestType,
    Uuid().v4(),
    CreateActorRequest(path, mailboxSize, useExistingActor),
  );
}

IsolateMessage createActorResponse(
  String correlationId,
  bool success,
  String message,
) {
  return IsolateMessage(
    createActorResponseType,
    correlationId,
    CreateActorResponse(success, message),
  );
}

class CreateActorRequest {
  final Uri path;
  final int? mailboxSize;
  final bool useExistingActor;

  CreateActorRequest(this.path, this.mailboxSize, this.useExistingActor);
}

class CreateActorResponse {
  final bool success;
  final String message;

  CreateActorResponse(this.success, this.message);
}
