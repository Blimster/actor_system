/// A constant to be used to initialize an actor after it is created.
const initMsg = InitMessage();

/// A constant to be used to shutdown an actor.
const shutdownMsg = ShutdownMessage();

class InitMessage {
  const InitMessage();

  @override
  String toString() => 'initMsg';
}

class ShutdownMessage {
  const ShutdownMessage();

  @override
  String toString() => 'shutdownMsg';
}
