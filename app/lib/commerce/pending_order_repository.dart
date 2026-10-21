import 'order_models.dart';
export 'order_models.dart';

enum PendingOrderFailureKind {
  invalidInput,
  accessRequired,
  actorChanged,
  invalidResponse,
  timedOut,
  requestFailed,
}

final class PendingOrderFailure implements Exception {
  const PendingOrderFailure(this.kind);
  final PendingOrderFailureKind kind;
  String get message => switch (kind) {
    PendingOrderFailureKind.invalidInput =>
      'Check the order intent and page settings.',
    PendingOrderFailureKind.accessRequired =>
      'Verify account access before reading order intents.',
    PendingOrderFailureKind.actorChanged =>
      'The signed-in account changed. Reopen order intents.',
    PendingOrderFailureKind.invalidResponse => 'The order-intent response could not be verified. Refresh before continuing.',
    PendingOrderFailureKind.timedOut =>
      'Loading order intents timed out. Check your connection and refresh.',
    PendingOrderFailureKind.requestFailed =>
      'Unable to read order intents. Check your connection and account access.',
  };
  @override
  String toString() => message;
}

/// Own safe intent history only. No creation, checkout, payment, approval,
/// entitlement or delivery API. actorId is a local identity guard, never a
/// caller-supplied server ownership selector. Admission/RLS remain authoritative.
abstract class PendingOrderRepository {
  Future<PendingOrder?> getOwnOrder({
    required String actorId,
    required String orderId,
  });
  Future<PendingOrderPage> listOwnOrders({
    required String actorId,
    PendingOrderCursor? cursor,
    int limit = pendingOrderDefaultLimit,
  });
}
