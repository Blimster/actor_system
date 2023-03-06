import 'package:metrics/metrics.dart';

/// Provides metrics for an actor system.
abstract class ActorSystemMetrics {
  /// The load of the system.
  double get load;

  /// The number of pending messages in the system.
  int get pendingMessages;
}

class MetricsImpl implements ActorSystemMetrics {
  final Meter meter = Meter();
  final Map<Uri, int> _pendingMessages = {};

  void update(Uri path, int processingTimeMs, int mailBoxLength) {
    meter.mark(processingTimeMs);
    _pendingMessages[path] = mailBoxLength;
  }

  @override
  double get load {
    return meter.oneMinuteRate;
  }

  @override
  int get pendingMessages => _pendingMessages.values.fold(0, (a, b) => a + b);
}
