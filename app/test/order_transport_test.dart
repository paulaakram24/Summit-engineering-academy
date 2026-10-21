import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:summit_academy/commerce/pending_order_repository.dart';
import 'package:summit_academy/commerce/supabase_pending_order_repository.dart';

import 'order_models_test.dart'
    show orderId, newerTieId, instant, orderRow, envelope, cursor;

const actorA = '11111111-1111-4111-8111-111111111111';
const actorB = '22222222-2222-4222-8222-222222222222';

void main() {
  late SupabaseClient client;
  late SupabasePendingOrderRepository repository;
  late List<http.Request> requests;
  Object? response;
  String? rawBody;
  var status = 200;
  Object? networkError;
  Completer<http.Response>? pending;

  Future<void> signIn(
    String actor, {
    int lifetime = 3600,
  }) => client.auth.setInitialSession(
    jsonEncode({
      'access_token':
          '${base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}')).replaceAll('=', '')}.${base64Url.encode(utf8.encode(jsonEncode({'sub': actor, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + lifetime}))).replaceAll('=', '')}.synthetic-signature',
      'token_type': 'bearer',
      'refresh_token': 'synthetic-refresh',
      'user': {
        'id': actor,
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-10-21T00:00:00Z',
      },
    }),
  );
  setUp(() async {
    requests = [];
    response = orderRow();
    status = 200;
    rawBody = null;
    networkError = null;
    pending = null;
    client = SupabaseClient(
      'https://example.test',
      'sb_publishable_test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (networkError != null) throw networkError!;
        if (pending != null && request.url.path.startsWith('/rest/')) {
          return pending!.future;
        }
        return http.Response(
          rawBody ?? jsonEncode(response),
          status,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    repository = SupabasePendingOrderRepository(client);
    await signIn(actorA);
  });
  tearDown(() => client.dispose());
  Map<String, dynamic> body() =>
      jsonDecode(requests.last.body) as Map<String, dynamic>;
  Matcher failure(PendingOrderFailureKind kind) => isA<PendingOrderFailure>()
      .having((error) => error.kind, 'kind', kind)
      .having(
        (error) => error.toString(),
        'sanitized',
        isNot(contains('PRIVATE_CANARY')),
      );
  Future<Object?> read(String action, {String actor = actorA}) =>
      action == 'get'
      ? repository.getOwnOrder(actorId: actor, orderId: orderId)
      : repository.listOwnOrders(actorId: actor);
  void prepare(String action) {
    response = action == 'get' ? orderRow() : envelope([orderRow()]);
  }

  http.Response reply(http.Request request, {int code = 200}) => http.Response(
    jsonEncode(response),
    code,
    request: request,
    headers: {'content-type': 'application/json'},
  );

  test(
    'get calls only the own-history RPC with exact order ID and pinned JWT',
    () async {
      final token = client.auth.currentSession!.accessToken;
      final order = await repository.getOwnOrder(
        actorId: actorA,
        orderId: orderId,
      );
      expect(order!.id, orderId);
      expect(order.state, PendingOrderState.pending);
      expect(requests.single.url.path, '/rest/v1/rpc/get_own_order');
      expect(requests.single.method, 'POST');
      expect(body(), {'p_order_id': orderId});
      expect(requests.single.headers['authorization'], 'Bearer $token');
      expect(client.headers['Authorization'], isNot('Bearer $token'));
    },
  );
  test('get null remains unavailable without exposing cross-owner versus missing distinction', () async {
    response = null;
    expect(
      await repository.getOwnOrder(actorId: actorA, orderId: orderId),
      isNull,
    );
    expect(
      await repository.getOwnOrder(actorId: actorA, orderId: newerTieId),
      isNull,
    );
    expect(requests, hasLength(2));
  });
  test(
    'get rejects wrong order entity with otherwise valid ten-field baseline',
    () async {
      response = orderRow(id: newerTieId);
      await expectLater(
        read('get'),
        throwsA(failure(PendingOrderFailureKind.invalidResponse)),
      );
    },
  );
  test(
    'valid UUID case variants are not mistaken for actor/entity switches',
    () async {
      response = {...orderRow(), 'id': orderId.toUpperCase()};
      final result = await repository.getOwnOrder(
        actorId: actorA.toUpperCase(),
        orderId: orderId.toUpperCase(),
      );
      expect(result!.id, orderId);
      expect(body(), {'p_order_id': orderId.toUpperCase()});
    },
  );
  test('list defaults to exact paired null cursor and limit20 without actor/ownership filters', () async {
    response = envelope([orderRow()]);
    final page = await repository.listOwnOrders(actorId: actorA);
    expect(page.items.single.id, orderId);
    expect(page.hasMore, isFalse);
    expect(page.nextCursor, isNull);
    expect(requests.single.url.path, '/rest/v1/rpc/list_own_orders');
    expect(body(), {
      'p_before_created_at': null,
      'p_before_id': null,
      'p_limit': 20,
    });
  });
  test('list sends cursor as exact UTC microseconds and paired UUID, accepts maximum50', () async {
    final boundary = cursor(id: newerTieId);
    response = envelope([orderRow()]);
    await repository.listOwnOrders(
      actorId: actorA,
      cursor: boundary,
      limit: 50,
    );
    expect(body(), {
      'p_before_created_at': instant,
      'p_before_id': newerTieId,
      'p_limit': 50,
    });
  });
  test(
    'empty list is an exact empty envelope, not null or missing fields',
    () async {
      response = envelope([]);
      final result = await repository.listOwnOrders(actorId: actorA);
      expect(result.items, isEmpty);
      expect(result.hasMore, isFalse);
      expect(result.nextCursor, isNull);
      for (final malformed in [
        null,
        {},
        {'items': []},
        {'items': [], 'has_more': false},
      ]) {
        response = malformed;
        await expectLater(
          read('list'),
          throwsA(failure(PendingOrderFailureKind.invalidResponse)),
        );
      }
    },
  );
  test(
    'list page count, ordering, duplicates and boundary are all verified',
    () async {
      for (final scenario in [
        'duplicate',
        'reverse',
        'over-limit',
        'boundary-id',
        'newer-than-boundary',
        'wrong-cursor',
        'short-more',
        'bad-boolean',
        'extra-envelope',
      ]) {
        PendingOrderCursor? boundary;
        var limit = 2;
        response = envelope([orderRow(id: newerTieId), orderRow()]);
        switch (scenario) {
          case 'duplicate':
            response = envelope([orderRow(), orderRow()]);
          case 'reverse':
            response = envelope([orderRow(), orderRow(id: newerTieId)]);
          case 'over-limit':
            limit = 1;
          case 'boundary-id':
            boundary = cursor(id: newerTieId);
          case 'newer-than-boundary':
            boundary = cursor(createdAt: '2026-10-20T00:00:00Z');
          case 'wrong-cursor':
            response = {
              ...envelope([orderRow(id: newerTieId), orderRow()], more: true),
              'next_cursor': {
                'created_at': '2026-10-21T12:34:56.123455Z',
                'id': orderId,
              },
            };
          case 'short-more':
            response = envelope([orderRow()], more: true);
          case 'bad-boolean':
            response = {...envelope([]), 'has_more': 'false'};
          case 'extra-envelope':
            response = {...envelope([]), 'buyer_id': 'PRIVATE_CANARY'};
        }
        await expectLater(
          repository.listOwnOrders(
            actorId: actorA,
            cursor: boundary,
            limit: limit,
          ),
          throwsA(failure(PendingOrderFailureKind.invalidResponse)),
          reason: scenario,
        );
      }
    },
  );
  test('full has-more page binds next cursor to last returned row and accepts following page', () async {
    response = envelope([orderRow(id: newerTieId), orderRow()], more: true);
    final first = await repository.listOwnOrders(actorId: actorA, limit: 2);
    expect(first.nextCursor, cursor());
    expect(first.hasMore, isTrue);
    response = envelope([
      orderRow(id: newerTieId, createdAt: '2026-10-21T12:34:56.123455Z'),
    ]);
    final second = await repository.listOwnOrders(
      actorId: actorA,
      cursor: first.nextCursor,
      limit: 2,
    );
    expect(second.items.single.createdAt.microsecond, 455);
    expect(body()['p_before_created_at'], instant);
    // Cross-page accumulated-ID rejection belongs to the future list consumer.
  });
  test(
    'frozen model failures become sanitized transport failures for both reads',
    () async {
      for (final malformed in [
        {...orderRow(), 'buyer_id': 'PRIVATE_CANARY'},
        {...orderRow(), 'state': 'paid'},
        {...orderRow(), 'price_piasters': '12345'},
        {...orderRow(), 'kind': 'bundle'},
        {...orderRow(), 'created_at': '2026-02-30T00:00:00Z'},
        {...orderRow()}..remove('session_id'),
      ]) {
        response = malformed;
        await expectLater(
          read('get'),
          throwsA(failure(PendingOrderFailureKind.invalidResponse)),
        );
        response = envelope([malformed]);
        await expectLater(
          read('list'),
          throwsA(failure(PendingOrderFailureKind.invalidResponse)),
        );
      }
    },
  );
  test(
    'bad actor/order UUIDs and out-of-range limits fail before network',
    () async {
      for (final invalid in ['', 'bad', '$actorA\n']) {
        await expectLater(
          repository.getOwnOrder(actorId: invalid, orderId: orderId),
          throwsA(failure(PendingOrderFailureKind.invalidInput)),
        );
        await expectLater(
          repository.getOwnOrder(actorId: actorA, orderId: invalid),
          throwsA(failure(PendingOrderFailureKind.invalidInput)),
        );
        await expectLater(
          repository.listOwnOrders(actorId: invalid),
          throwsA(failure(PendingOrderFailureKind.invalidInput)),
        );
      }
      for (final limit in [-1, 0, 51]) {
        await expectLater(
          repository.listOwnOrders(actorId: actorA, limit: limit),
          throwsA(failure(PendingOrderFailureKind.invalidInput)),
        );
      }
      expect(requests, isEmpty);
    },
  );
  for (final action in ['get', 'list']) {
    test(
      '$action rejects actor mismatch before transmission, never sends buyer ID',
      () async {
        await signIn(actorB);
        await expectLater(
          read(action),
          throwsA(failure(PendingOrderFailureKind.actorChanged)),
        );
        expect(requests, isEmpty);
        prepare(action);
        await read(action, actor: actorB);
        expect(body().containsKey('actor_id'), isFalse);
        expect(body().containsKey('buyer_id'), isFalse);
      },
    );
    test(
      '$action blocks absent and expired sessions before history requests',
      () async {
        await signIn(actorA, lifetime: -100);
        await expectLater(
          read(action),
          throwsA(failure(PendingOrderFailureKind.accessRequired)),
        );
        expect(requests, isEmpty);
        await client.auth.signOut(scope: SignOutScope.local);
        requests.clear();
        await expectLater(
          read(action),
          throwsA(failure(PendingOrderFailureKind.accessRequired)),
        );
        expect(requests, isEmpty);
      },
    );
    for (final change in ['switch', 'A-B-A', 'signout', 'expiry']) {
      test(
        '$action rejects late $change result with captured JWT still pinned',
        () async {
          prepare(action);
          pending = Completer<http.Response>();
          final token = client.auth.currentSession!.accessToken;
          final expected = change == 'expiry'
              ? PendingOrderFailureKind.accessRequired
              : PendingOrderFailureKind.actorChanged;
          final assertion = expectLater(
            read(action),
            throwsA(failure(expected)),
          );
          await Future<void>.delayed(Duration.zero);
          final request = requests.single;
          switch (change) {
            case 'switch':
              await signIn(actorB);
            case 'A-B-A':
              await signIn(actorB);
              await signIn(actorA);
            case 'signout':
              await client.auth.signOut(scope: SignOutScope.local);
            case 'expiry':
              await signIn(actorA, lifetime: -100);
          }
          pending!.complete(reply(request));
          await assertion;
          expect(request.headers['authorization'], 'Bearer $token');
          expect(
            requests.where((r) => r.url.path.startsWith('/rest/')),
            hasLength(1),
          );
        },
      );
    }
    test(
      '$action supports same-actor token refresh without swapping pinned token',
      () async {
        prepare(action);
        pending = Completer<http.Response>();
        final token = client.auth.currentSession!.accessToken;
        final future = read(action);
        await Future<void>.delayed(Duration.zero);
        final request = requests.single;
        await signIn(actorA, lifetime: 7200);
        pending!.complete(reply(request));
        expect(await future, isNotNull);
        expect(request.headers['authorization'], 'Bearer $token');
        expect(client.auth.currentSession!.accessToken, isNot(token));
      },
    );
    test(
      '$action blocks a custom-token-only client without authenticated user',
      () async {
        var calls = 0;
        final isolated = SupabaseClient(
          'https://example.test',
          'sb_publishable_test',
          accessToken: () async => 'PRIVATE_CANARY',
          httpClient: MockClient((_) async {
            calls++;
            throw StateError('Must not transmit');
          }),
        );
        addTearDown(isolated.dispose);
        repository = SupabasePendingOrderRepository(isolated);
        await expectLater(
          read(action),
          throwsA(failure(PendingOrderFailureKind.accessRequired)),
        );
        expect(calls, 0);
      },
    );
  }
  for (final server in [
    ('42501', 'order_access_required', PendingOrderFailureKind.accessRequired),
    ('22023', 'invalid_order_input', PendingOrderFailureKind.invalidInput),
    ('42501', 'PRIVATE_CANARY', PendingOrderFailureKind.requestFailed),
  ]) {
    test(
      'server ${server.$1}/${server.$2} maps safely for both reads, not null/empty',
      () async {
        status = 403;
        response = {
          'code': server.$1,
          'message': server.$2,
          'details': 'PRIVATE_CANARY',
          'hint': 'PRIVATE_CANARY',
        };
        for (final action in ['get', 'list']) {
          await expectLater(read(action), throwsA(failure(server.$3)));
        }
        expect(requests, hasLength(2));
      },
    );
  }
  test(
    'late server failure after identity change cannot report old-account state',
    () async {
      pending = Completer<http.Response>();
      final assertion = expectLater(
        read('get'),
        throwsA(failure(PendingOrderFailureKind.actorChanged)),
      );
      await Future<void>.delayed(Duration.zero);
      final request = requests.single;
      await signIn(actorB);
      response = {
        'code': '42501',
        'message': 'PRIVATE_CANARY',
        'details': 'PRIVATE_CANARY',
      };
      pending!.complete(reply(request, code: 403));
      await assertion;
    },
  );
  test('timeouts never auto-retry or accept late data; only explicit later read starts new call', () async {
    repository = SupabasePendingOrderRepository(
      client,
      timeout: const Duration(milliseconds: 20),
    );
    pending = Completer<http.Response>();
    await expectLater(
      read('get'),
      throwsA(failure(PendingOrderFailureKind.timedOut)),
    );
    expect(requests, hasLength(1));
    pending!.complete(reply(requests.single));
    pending = null;
    expect(
      (await repository.getOwnOrder(actorId: actorA, orderId: orderId))!.id,
      orderId,
    );
    expect(requests, hasLength(2));
  });
  test(
    'network failures are sanitized and issue no fallback or automatic retry',
    () async {
      networkError = StateError('PRIVATE_CANARY');
      for (final action in ['get', 'list']) {
        await expectLater(
          read(action),
          throwsA(failure(PendingOrderFailureKind.requestFailed)),
        );
      }
      expect(requests, hasLength(2));
      expect(requests.map((r) => r.url.path).toSet(), {
        '/rest/v1/rpc/get_own_order',
        '/rest/v1/rpc/list_own_orders',
      });
    },
  );
  test(
    'malformed JSON response is sanitized without exposing raw protected body',
    () async {
      rawBody = '{"PRIVATE_CANARY":';
      await expectLater(
        read('get'),
        throwsA(
          isA<PendingOrderFailure>().having(
            (e) => e.toString(),
            'sanitized',
            isNot(contains('PRIVATE_CANARY')),
          ),
        ),
      );
      expect(requests, hasLength(1));
    },
  );
  test('all failures render fixed messages without JWTs, order snapshots or private details', () {
    for (final kind in PendingOrderFailureKind.values) {
      final error = PendingOrderFailure(kind);
      expect(error.message, isNotEmpty);
      expect(error.toString(), error.message);
      expect(
        error.toString(),
        isNot(contains(client.auth.currentSession!.accessToken)),
      );
      expect(
        error.toString(),
        isNot(contains(orderRow()['course_title_snapshot'])),
      );
      expect(error.toString(), isNot(contains('PRIVATE_CANARY')));
    }
  });
}
