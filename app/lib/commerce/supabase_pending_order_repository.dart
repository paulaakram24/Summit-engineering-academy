import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../catalog/catalog_models.dart' show isCatalogUuid;
import 'pending_order_repository.dart';

/// Only the two own-history RPCs. No table fallback, global header mutation,
/// custom-token client, local cache, creation or automatic retry is introduced.
class SupabasePendingOrderRepository implements PendingOrderRepository {
  SupabasePendingOrderRepository(
    this.client, {
    this.timeout = const Duration(seconds: 20),
  });
  final SupabaseClient client;
  final Duration timeout;

  void _input(bool valid) {
    if (!valid) {
      throw const PendingOrderFailure(PendingOrderFailureKind.invalidInput);
    }
  }

  Session _session() {
    try {
      final session = client.auth.currentSession;
      final user = client.auth.currentUser;
      if (session != null &&
          user != null &&
          isCatalogUuid(user.id) &&
          session.user.id.toLowerCase() == user.id.toLowerCase() &&
          session.accessToken.isNotEmpty &&
          !session.isExpired) {
        return session;
      }
    } catch (_) {
      /* A custom token is not an authenticated GoTrue identity. */
    }
    throw const PendingOrderFailure(PendingOrderFailureKind.accessRequired);
  }

  void _actor(String captured, bool changed) {
    if (changed || _session().user.id.toLowerCase() != captured.toLowerCase()) {
      throw const PendingOrderFailure(PendingOrderFailureKind.actorChanged);
    }
  }

  Future<T> _read<T>(
    String actorId,
    String rpc,
    Map<String, dynamic> params,
    T Function(Object?) decode,
  ) async {
    final session = _session();
    final actor = session.user.id;
    if (actor.toLowerCase() != actorId.toLowerCase()) {
      throw const PendingOrderFailure(PendingOrderFailureKind.actorChanged);
    }
    var changed = false;
    final subscription = client.auth.onAuthStateChange.listen(
      (state) {
        if (state.session?.user.id.toLowerCase() != actor.toLowerCase()) {
          changed = true;
        }
      },
      onError: (Object _) {
        changed = true;
      },
    );
    try {
      _actor(actor, changed);
      final result = await client
          .rpc(rpc, params: params)
          .setHeader('Authorization', 'Bearer ${session.accessToken}')
          .timeout(timeout);
      _actor(actor, changed);
      return decode(result);
    } on PendingOrderFailure {
      rethrow;
    } on PendingOrderModelFailure {
      throw const PendingOrderFailure(PendingOrderFailureKind.invalidResponse);
    } on PostgrestException catch (error) {
      throw PendingOrderFailure(switch ((error.code, error.message)) {
        ('42501', 'order_access_required') =>
          PendingOrderFailureKind.accessRequired,
        ('22023', 'invalid_order_input') =>
          PendingOrderFailureKind.invalidInput,
        _ => PendingOrderFailureKind.requestFailed,
      });
    } on TimeoutException {
      throw const PendingOrderFailure(PendingOrderFailureKind.timedOut);
    } on FormatException {
      throw const PendingOrderFailure(PendingOrderFailureKind.invalidResponse);
    } catch (_) {
      throw const PendingOrderFailure(PendingOrderFailureKind.requestFailed);
    } finally {
      await subscription.cancel();
      _actor(actor, changed);
    }
  }

  @override
  Future<PendingOrder?> getOwnOrder({
    required String actorId,
    required String orderId,
  }) async {
    _input(isCatalogUuid(actorId) && isCatalogUuid(orderId));
    return _read(actorId, 'get_own_order', {'p_order_id': orderId}, (value) {
      if (value == null) return null;
      final order = PendingOrder.fromJson(value);
      if (order.id != orderId.toLowerCase()) {
        throw const PendingOrderFailure(
          PendingOrderFailureKind.invalidResponse,
        );
      }
      return order;
    });
  }

  @override
  Future<PendingOrderPage> listOwnOrders({
    required String actorId,
    PendingOrderCursor? cursor,
    int limit = pendingOrderDefaultLimit,
  }) async {
    _input(
      isCatalogUuid(actorId) && limit >= 1 && limit <= pendingOrderMaxLimit,
    );
    return _read(
      actorId,
      'list_own_orders',
      {
        'p_before_created_at': cursor?.createdAt.toIso8601String(),
        'p_before_id': cursor?.id,
        'p_limit': limit,
      },
      (value) => PendingOrderPage.fromJson(value, limit: limit, after: cursor),
    );
  }
}
