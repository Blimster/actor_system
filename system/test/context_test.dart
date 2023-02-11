import 'dart:async';

import 'package:actor_system/actor_system.dart';
import 'package:test/test.dart';

void main() {
  late ActorSystem system;

  setUp(() {
    system = ActorSystem();
  });

  group('base context', () {
    test('an actor ref can be created', () async {
      final actor = await system.createActor(Uri.parse('/actor'), factory: (path) => (ctx, msg) => null);
      expect(actor.path, equals(Uri.parse('actor://local/actor')));
    });

    test('creating an actor with init sends an initMsg', () async {
      final completer = Completer<void>();
      await system.createActor(
        Uri.parse('/actor'),
        factory: (path) => (ctx, msg) {
          if (msg == initMsg) {
            completer.complete();
          }
        },
        sendInit: true,
      );
      expect(completer.future, completion(null));
    }, timeout: Timeout(Duration(seconds: 1)));

    test('creating an actor without a matching factory throws an exception', () async {
      expect(() async {
        await system.createActor(Uri.parse('/actor'));
      }, throwsA(predicate((e) => e is NoFactoryFound && e.message.contains('/actor'))));
    });

    test('an actor ref can be looked up', () async {
      await system.createActor(Uri.parse('/actor'), factory: (path) => (ctx, msg) => null);
      final actor = await system.lookupActor(Uri.parse('/actor'));
      expect(actor?.path, equals(Uri.parse('actor://local/actor')));
    });

    test('actor refs can be looked up', () async {
      await system.createActor(Uri.parse('/foo'), factory: (path) => (ctx, msg) => null);
      await system.createActor(Uri.parse('/foo/1'), factory: (path) => (ctx, msg) => null);
      await system.createActor(Uri.parse('/foo/2'), factory: (path) => (ctx, msg) => null);
      await system.createActor(Uri.parse('/bar/1'), factory: (path) => (ctx, msg) => null);
      final actors = await system.lookupActors(Uri.parse('/foo'));
      expect(actors, hasLength(2));
      expect(
        actors.map((e) => e.path),
        containsAll([Uri.parse('actor://local/foo/1'), Uri.parse('actor://local/foo/2')]),
      );
    });
  });

  group('system context', () {
    test('a registered factory creates actor for a matching path', () async {
      system.addActorFactory(patternMatcher('/actor'), (path) => (ctx, msg) => null);
      final actor = await system.createActor(Uri.parse('/actor/foo'));
      expect(actor, isNotNull);
    });

    test('external create is called', () async {
      system.externalCreateActor = (path, mailboxSize) async {
        return TestRef(path);
      };
      final actorRef = await system.createActor(Uri(host: 'foo', path: '/actor'));
      expect(actorRef, isA<TestRef>());
      expect(actorRef.path, equals(Uri(scheme: 'actor', host: 'foo', path: '/actor')));
    });

    test('external lookup actor is called', () async {
      system.externalLookupActor = (path) async {
        return TestRef(path);
      };
      final actorRef = await system.lookupActor(Uri(host: 'foo', path: '/actor'));
      expect(actorRef, isA<TestRef>());
      expect(actorRef?.path, equals(Uri(scheme: 'actor', host: 'foo', path: '/actor')));
    });

    test('external lookup actors is called', () async {
      system.externalLookupActors = (path) async {
        return [TestRef(path)];
      };
      final actorRef = await system.lookupActors(Uri(host: 'foo', path: '/actor'));
      expect(actorRef.map((e) => e.path), containsAll([Uri(scheme: 'actor', host: 'foo', path: '/actor')]));
    });
  });

  group('actor context', () {
    test('sender, replyTo, correlationId and current is set', () async {
      final completer = Completer<List<String?>>();

      final sender = await system.createActor(actorPath('/sender'), factory: (_) => (ctx, msg) => null);
      final replyTo = await system.createActor(actorPath('/replyTo'), factory: (_) => (ctx, msg) => null);

      final actorRef = await system.createActor(
        Uri.parse('/actor'),
        factory: (_) => (ActorContext ctx, msg) {
          completer.complete([
            ctx.sender?.path.toString(),
            ctx.replyTo?.path.toString(),
            ctx.correlationId,
            ctx.current.path.toString(),
          ]);
        },
      );
      await actorRef.send(
        'message',
        sender: sender,
        replyTo: replyTo,
        correlationId: 'correlId',
      );
      expect(
          completer.future,
          completion([
            'actor://local/sender',
            'actor://local/replyTo',
            'correlId',
            'actor://local/actor',
          ]));
    }, timeout: Timeout(Duration(seconds: 1)));
  });
}

class TestRef implements ActorRef {
  @override
  final Uri path;

  TestRef(this.path);

  @override
  Future<void> send(Object? message, {ActorRef? sender, ActorRef? replyTo, String? correlationId}) {
    throw UnimplementedError();
  }

  @override
  Future<void> shutdown() {
    throw UnimplementedError();
  }
}
