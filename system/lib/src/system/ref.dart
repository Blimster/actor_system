import 'dart:async';
import 'dart:collection';

import 'package:actor_system/src/system/actor.dart';
import 'package:actor_system/src/system/context.dart';
import 'package:actor_system/src/system/exceptions.dart';
import 'package:actor_system/src/system/messages.dart';
import 'package:logging/logging.dart';

/// Use this constant as a key for a [Zone] value to set an actor as a sender.
const zoneSenderKey = 'actor_system:sender';

class ActorMessageEnvelope {
  final Object? message;
  final ActorRef? replyTo;
  final String? correlationId;

  ActorMessageEnvelope(this.message, this.replyTo, this.correlationId);
}

/// A reference to an actor. The only way to communicate with an actor is to
/// send messages to it using the API of the [ActorRef].
class ActorRef {
  final Logger _log;
  final Uri path;
  final int _maxMailBoxSize;
  final Queue<ActorMessageEnvelope> _mailbox = Queue();
  final ActorFactory _factory;
  final ActorContext _context;
  final void Function(Uri path, int processingTimeMs, int mailBoxLength) _onMessageProcessed;
  final void Function(String path) _onActorStopped;
  Actor _actor;
  bool _isProcessing = false;
  bool _stopped = false;

  ActorRef._(
    this.path,
    this._maxMailBoxSize,
    this._actor,
    this._factory,
    this._context,
    this._onMessageProcessed,
    this._onActorStopped,
  ) : _log = Logger('actor_system.system.ActorRef:${path.toString()}');

  /// Sends a message to the actor referenced by this
  /// [ActorRef]. It is guaranteed, that an actor processes
  /// only one message at a time.
  ///
  /// If a message is sent to an actor that currently
  /// processes another message, the new message is put
  /// into the mailbox of the actor. Messages are
  /// processed in the order they arrive at the actor.
  ///
  /// The returned [Future] completes when the message was
  /// successfully added to the actors mailbox.
  ///
  /// If an error occurs while a message is processed and
  /// is not handled by the actor itself, the actor is
  /// thrown away and recreated using the factory provided
  /// when the actor was created. The messages in mailbox
  /// of the actor remain.
  Future<void> send(Object? message, {ActorRef? replyTo, String? correlationId}) async {
    _log.info('send < message=${message?.runtimeType}, replyTo=$replyTo, correlationId=$correlationId');
    if (_stopped) {
      throw ActorStopped();
    }
    if (_mailbox.length >= _maxMailBoxSize) {
      throw MailboxFull();
    }

    _log.fine('send | adding message at position ${_mailbox.length}');
    _mailbox.addLast(ActorMessageEnvelope(message, replyTo, correlationId));
    _handleMessage();

    // message was added to mailbox
    _log.info('send > null');
    return;
  }

  void _handleMessage() {
    Future(() async {
      _log.fine('handleMessage <');
      _log.fine('handleMessage | isProcessing=$_isProcessing, mailboxSize=${_mailbox.length}');
      if (!_isProcessing && _mailbox.isNotEmpty) {
        _isProcessing = true;
        try {
          final envelope = _mailbox.removeFirst();
          if (envelope.message == shutdownMsg) {
            _log.fine('handleMessage | received shutdown message.');
            _stopped = true;
            _mailbox.clear();
            _onActorStopped(path.path);
          }
          final zoneActor = Zone.current[zoneSenderKey] as ActorRef?;
          prepareContext(_context, this, zoneActor, envelope.replyTo, envelope.correlationId);
          _log.fine('handleMessage | calling actor with message of type ${envelope.message?.runtimeType}');
          final sw = Stopwatch();
          sw.start();
          runZoned(
            () => _actor(_context, envelope.message),
            zoneValues: {zoneSenderKey: _context.current},
          );
          sw.stop();
          _onMessageProcessed(path, sw.elapsedMilliseconds, _mailbox.length);
          _log.fine('handleMessage | back from actor call');
        } catch (error) {
          _log.warning('handleMessage | unhandled error while calling actor: $error');
          if (error is! SkipMessage) {
            _actor = await _factory(path);
            _log.fine('handleMessage | actor recreated');
          }
        } finally {
          _isProcessing = false;
          if (_mailbox.isNotEmpty) {
            _log.info('more messages in mailbox. trigger handleMessage again...');
            _handleMessage();
          }
        }
      }
      _log.fine('handleMessage >');
    });
  }

  /// Sends a [shutdownMsg] to the actor. After the shutdown
  /// message was processed, the actor is stopped and its
  /// mailbox is cleared. Sending new message to a stopped
  /// actor leads to an exception.
  Future<void> shutdown() => send(shutdownMsg);

  @override
  String toString() => 'ActorRef(path=$path)';
}

ActorRef createActorRef(
  Uri path,
  int maxMailBoxSize,
  Actor actor,
  ActorFactory factory,
  ActorContext context,
  void Function(Uri path, int processingTimeMs, int mailBoxLength) onMessageProcessed,
  void Function(String path) onActorStopped,
) {
  return ActorRef._(path, maxMailBoxSize, actor, factory, context, onMessageProcessed, onActorStopped);
}
