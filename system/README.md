:warning: ALPHA :warning:

This package is in early stage of development. Breaking changes will happen very often. The package has no tests yet.

# Actor System

An implementation of the actor model in Dart.

## Features

- Create an actor system as a space for actors. All actors in the same system can communicate to each other.
- Create actors for a path.
- Lookup actors by a path.
- Send messages to an actor.
- Only process one message at a time, even if the processing is asynchronous.
- Restart an actor if the processing of a message fails with an exception.
- Create actors using a builder.
- Register global factories for actors. Factories are selected by the path an actor is created for.
- Register external create and lookup functions to connect multiple actor systems.

## Usage

An actor is a function that accepts a context and a message.

```dart
typedef Actor = FutureOr<void> Function(ActorContext ctx, Object? message);
```

An implementation of an actor could look like this:

```dart
void myActor(ActorContext ctx, Object? messge) {
    print(message);
}
```

The actor function should never be called directly. It is called by the actor system when a message is sent to the actor.

An actor is created by an actor factory. Like an actor, a factory is just a function that returns an actor for a given path.

```dart
typedef ActorFactory = FutureOr<Actor> Function(Uri path);
```

An implementation of a factory could look like this:

```dart
Actor myFactory(Uri path) {
    return myActor;
}
```

An actor lives in an actor system. An actor system provides an API to create and lookup actors.

```dart
final system = ActorSystem();
final actor1 = await system.createActor(Uri.parse('/foo/bar/1'), factory: myFactory);
final actor2 = await system.lookupAcor(Uri.parse('/foo/bar/2'));
```

The result of a call to `createActor()` and `lookupActor()` is a reference to an actor (class `ActorRef`). You can use the reference to send messages to the actor.

```dart
final actor = await system.lookupAcor(Uri.parse('/foo/bar'));
await actor.send('message1');
await actor.send('message2');
```

Messages sent to an actor will be placed in the actors mailbox. As soon as messages are in the mailbox, the actor starts processing the messages in the order they were put in the actors mailbox. The future returned by the `send()` function completes, when the message was placed in the mailbox of the actor.

A main concept of actors is the capsulation of state. As an actor is just a function, you can't store state in it directly. Here is an example for handling state in an actor.

```dart
Actor countingActor() {
    var counter = 0;

    return (ctx, message) {
        counter++;
        print('received $message on call #${counter}');
    }
}
```
