import 'dart:collection';

import 'package:actor_system/src/system/actor.dart';
import 'package:actor_system/src/system/context.dart';
import 'package:logging/logging.dart';

class ActorMessageEnvelope {
  final Object? message;
  final ActorRef? replyTo;

  ActorMessageEnvelope(this.message, this.replyTo);
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
  Actor _actor;
  bool _isProcessing = false;

  ActorRef._(
    this.path,
    this._maxMailBoxSize,
    this._actor,
    this._factory,
    this._context,
  ) : _log = Logger('ActorRef:${path.toString()}');

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
  Future<void> send(Object? message, {ActorRef? replyTo}) async {
    _log.info('send < message=${message?.runtimeType}, replyTo=$replyTo');
    if (_mailbox.length >= _maxMailBoxSize) {
      throw Exception('mailbox is full! max size is $_maxMailBoxSize.');
    }

    _log.fine('send | adding message at position ${_mailbox.length}');
    _mailbox.addLast(ActorMessageEnvelope(message, replyTo));
    _handleMessage();

    // message was added to mailbox
    _log.info('send > null');
    return null;
  }

  void _handleMessage() {
    Future(() async {
      _log.fine('handleMessage <');
      _log.fine('handleMessage | isProcessing=$_isProcessing, mailboxSize=${_mailbox.length}');
      if (!_isProcessing && _mailbox.isNotEmpty) {
        _isProcessing = true;
        try {
          final envelope = _mailbox.removeFirst();
          prepareContext(_context, this, envelope.replyTo);
          _log.fine('handleMessage | calling actor with message of type ${envelope.message?.runtimeType}');
          await _actor(_context, envelope.message);
          _log.fine('handleMessage | back from actor call');
        } catch (error) {
          _log.warning('handleMessage | unhandled error while calling actor: $error');
          _actor = await _factory(path);
          _log.fine('handleMessage | actor recreated');
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

  @override
  String toString() => 'ActorRef(path=$path)';
}

ActorRef createActorRef(
  Uri path,
  int maxMailBoxSize,
  Actor actor,
  ActorFactory factory,
  ActorContext context,
) {
  return ActorRef._(path, maxMailBoxSize, actor, factory, context);
}
