class CreateActorRequest {
  final Uri path;
  final int? mailboxSize;
  final bool useExistingActor;

  CreateActorRequest(this.path, this.mailboxSize, this.useExistingActor);
}
