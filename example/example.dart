import 'package:actor_system/actor_system.dart';

void main() async {
  final actorSystem = ActorSystem();
  final actorRef = await actorSystem.createActor(Uri.parse('/test'), testActor);
  actorRef.send(FooMessage('foo', 1000));
  actorRef.send(BarMessage('bar'));
}

class FooMessage {
  final String test;
  final int delay;

  FooMessage(this.test, this.delay);
}

class BarMessage {
  final String test;

  BarMessage(this.test);
}

void testActor(FactoryContext factoryContext) {
  Future<void> handleFooMessage(ActorContext c, FooMessage m) {
    print('foo: ${m.test}, delay: ${m.delay}');
    return Future.delayed(Duration(milliseconds: m.delay), () => null);
  }

  void handleBarMessage(ActorContext c, BarMessage m) {
    print('bar: ${m.test}');
  }

  factoryContext.registerMessageHandler(handleFooMessage);
  factoryContext.registerMessageHandler(handleBarMessage);
}
