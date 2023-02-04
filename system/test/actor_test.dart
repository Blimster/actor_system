import 'dart:async';

import 'package:actor_system/actor_system.dart';
import 'package:test/test.dart';

Future<ActorRef> createActor(ActorSystem system, Actor Function() actor) async {
  return system.createActor(Uri.parse('/actor'), factory: (_) => actor());
}

void main() {
  late ActorSystem system;

  setUp(() {
    system = ActorSystem();
  });

  test('a message sent to the actor is processed', () async {
    final completer = Completer<void>();
    final actor = await createActor(
        system,
        () => (ctx, msg) {
              if (msg == 'message') {
                completer.complete();
              }
            });
    await actor.send('message');
    expect(completer.future, completion(null));
  }, timeout: Timeout(Duration(seconds: 1)));

  test('an actor only processes one message at a time', () async {
    final completer = Completer<void>();
    var state = '';
    final actor = await createActor(
        system,
        () => (ctx, msg) async {
              if (msg == 'message1') {
                await Future.delayed(Duration(milliseconds: 100));
                state = 'message1';
              } else if (msg == 'message2' && state == 'message1') {
                completer.complete();
              }
            });
    await actor.send('message1');
    await actor.send('message2');

    expect(completer.future, completion(null));
  }, timeout: Timeout(Duration(seconds: 1)));

  test('an unhandled error restarts the actor', () async {
    final streamController = StreamController<int>();
    final actor = await createActor(system, () {
      var counter = 0;
      return (ctx, msg) {
        if (msg == 'error') {
          throw StateError('received error message');
        }
        counter++;
        streamController.add(counter);
      };
    });

    await actor.send('message');
    await actor.send('message');
    await actor.send('error');
    await actor.send('message');

    expect(streamController.stream, emitsInOrder([1, 2, 1]));
  });

  test('sending a message to an actor with a full mailbox throws an exception', () async {
    final actorRef = await system.createActor(actorPath('/actor'),
        factory: (_) => (ctx, msg) async => Future.delayed(Duration(seconds: 1)), mailboxSize: 1);

    await actorRef.send('');
    expect(() async => await actorRef.send(''), throwsA(isA<MailboxFull>()));
  });

  test('calling shutdown stops an actor', () async {
    final completer = Completer<void>();
    final actorRef = await system.createActor(
      actorPath('/actor'),
      factory: (_) => (ctx, msg) async {
        if (msg == shutdownMsg) {
          completer.complete();
        }
      },
    );
    await actorRef.shutdown();
    await completer.future;
    expect(actorRef.send(''), throwsA(isA<ActorStopped>()));
  }, timeout: Timeout(Duration(seconds: 1)));
}
