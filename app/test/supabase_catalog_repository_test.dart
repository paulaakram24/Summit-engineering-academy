import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:summit_academy/catalog/catalog_repository.dart';
import 'package:summit_academy/catalog/supabase_catalog_repository.dart';

import 'catalog_models_test.dart';

void main() {
  late SupabaseClient client;
  late SupabaseCatalogRepository repository;
  late List<http.Request> requests;
  Object? response;
  var status = 200;
  Object? networkError;
  Completer<http.Response>? pending;
  Future<void> signInAs(
    String id, {
    int lifetime = 3600,
  }) => client.auth.setInitialSession(
    jsonEncode({
      'access_token':
          '${base64Url.encode(utf8.encode('{"alg":"HS256","typ":"JWT"}')).replaceAll('=', '')}.${base64Url.encode(utf8.encode(jsonEncode({'sub': id, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + lifetime}))).replaceAll('=', '')}.synthetic-signature',
      'token_type': 'bearer',
      'refresh_token': 'synthetic-refresh',
      'user': {
        'id': id,
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-10-19T03:00:00Z',
      },
    }),
  );
  Matcher failure(CatalogFailureKind kind) => isA<CatalogFailure>()
      .having((e) => e.kind, 'kind', kind)
      .having(
        (e) => e.toString(),
        'sanitized',
        isNot(contains('PRIVATE_CANARY')),
      );
  setUp(() async {
    requests = [];
    response = catalogEnvelope([catalogCourseRow()]);
    status = 200;
    networkError = null;
    pending = null;
    client = SupabaseClient(
      'https://example.test',
      'sb_publishable_test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (networkError != null) throw networkError!;
        if (pending != null && request.url.path.contains('/rest/')) {
          return pending!.future;
        }
        return http.Response(
          jsonEncode(response),
          status,
          request: request,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    repository = SupabaseCatalogRepository(client);
    await signInAs(catalogActor);
  });
  tearDown(() => client.dispose());
  Map<String, dynamic> body() =>
      jsonDecode(requests.last.body) as Map<String, dynamic>;
  Future<Object?> read(String operation) => switch (operation) {
    'courses' => repository.listCourses(),
    'course' => repository.getCourse(catalogCourseId),
    'sessions' => repository.listSessions(catalogCourseId),
    'filters' => repository.getFilters(),
    _ => throw StateError('Unknown operation'),
  };
  void respondFor(String operation) {
    response = switch (operation) {
      'course' => catalogCourseRow(),
      'sessions' => catalogEnvelope([catalogSessionRow()]),
      'filters' => {
        'categories': ['Civil'],
        'levels': ['Beginner'],
      },
      _ => catalogEnvelope([catalogCourseRow()]),
    };
  }

  test('default course call sends exact read-only RPC parameters and pins actor JWT', () async {
    final token = client.auth.currentSession!.accessToken;
    expect((await repository.listCourses()).items.single.id, catalogCourseId);
    expect(requests.single.url.path, '/rest/v1/rpc/list_catalog_courses');
    expect(body(), {
      'p_search': '',
      'p_category': null,
      'p_level': null,
      'p_after_position': null,
      'p_after_id': null,
      'p_limit': 20,
    });
    expect(requests.single.headers['authorization'], 'Bearer $token');
    expect(client.headers['Authorization'], isNot('Bearer $token'));
  });
  test('padded returned category and level match normalized filters without changing display labels', () async {
    response = catalogEnvelope([
      {...catalogCourseRow(), 'category': '  Civil ', 'level': ' Beginner  '},
    ]);
    final result = await repository.listCourses(
      category: ' Civil  ',
      level: '  Beginner ',
    );
    expect(body()['p_category'], 'Civil');
    expect(body()['p_level'], 'Beginner');
    expect(result.items.single.category, '  Civil ');
    expect(result.items.single.level, ' Beginner  ');
  });
  test(
    'tabs and NBSP are not stripped from filter values or returned labels',
    () async {
      response = catalogEnvelope([
        {
          ...catalogCourseRow(),
          'category': '\tCivil\u00a0',
          'level': '\u00a0Beginner\t',
        },
      ]);
      final result = await repository.listCourses(
        category: ' \tCivil\u00a0 ',
        level: ' \u00a0Beginner\t ',
      );
      expect(body()['p_category'], '\tCivil\u00a0');
      expect(result.items.single.level, '\u00a0Beginner\t');
      await expectLater(
        repository.listCourses(category: 'Civil'),
        throwsA(failure(CatalogFailureKind.invalidResponse)),
      );
    },
  );
  test(
    'literal search symbols are preserved, only ASCII boundary spaces removed',
    () async {
      await repository.listCourses(
        search: '  %_\\\t\u00a0  ',
        category: '  ',
        level: '',
      );
      expect(body()['p_search'], '%_\\\t\u00a0');
      expect(body()['p_category'], isNull);
      expect(body()['p_level'], isNull);
    },
  );
  test('Unicode codepoint search/filter bounds accept exact maximum', () async {
    response = catalogEnvelope([]);
    await repository.listCourses(
      search: '😀' * 100,
      category: '😀' * 120,
      level: 'x' * 120,
    );
    expect(requests, hasLength(1));
  });
  for (final scenario in [
    'null-search',
    'long-search',
    'nul-search',
    'long-category',
    'long-level',
    'nul-filter',
    'zero-limit',
    'large-limit',
    'bad-cursor',
  ]) {
    test('invalid $scenario rejected before network', () async {
      await expectLater(
        repository.listCourses(
          search: scenario == 'null-search'
              ? null
              : scenario == 'long-search'
              ? '😀' * 101
              : scenario == 'nul-search'
              ? '\u0000'
              : '',
          category: scenario == 'long-category'
              ? 'x' * 121
              : scenario == 'nul-filter'
              ? '\u0000'
              : null,
          level: scenario == 'long-level' ? 'x' * 121 : null,
          limit: scenario == 'zero-limit'
              ? 0
              : scenario == 'large-limit'
              ? 51
              : 20,
          after: scenario == 'bad-cursor'
              ? const CatalogCursor(position: -1, id: catalogCourseId)
              : null,
        ),
        throwsA(failure(CatalogFailureKind.invalidInput)),
      );
      expect(requests, isEmpty);
    });
  }
  test(
    'paired keyset and maximum page size are transmitted unchanged',
    () async {
      response = catalogEnvelope([
        catalogCourseRow(id: catalogOtherId, position: 2),
      ]);
      await repository.listCourses(
        after: const CatalogCursor(position: 1, id: catalogCourseId),
        limit: 50,
      );
      expect(body()['p_after_position'], 1);
      expect(body()['p_after_id'], catalogCourseId);
      expect(body()['p_limit'], 50);
    },
  );
  test('course detail is same entity or null unavailable, never silently substitutes', () async {
    response = catalogCourseRow();
    expect((await repository.getCourse(catalogCourseId))!.id, catalogCourseId);
    expect(requests.last.url.path, '/rest/v1/rpc/get_catalog_course');
    expect(body(), {'p_course_id': catalogCourseId});
    response = null;
    expect(await repository.getCourse(catalogCourseId), isNull);
    response = catalogCourseRow(id: catalogOtherId);
    await expectLater(
      repository.getCourse(catalogCourseId),
      throwsA(failure(CatalogFailureKind.invalidResponse)),
    );
  });
  test('session outline parameters and parent identity are verified; unavailable parent is empty', () async {
    response = catalogEnvelope([catalogSessionRow()]);
    expect(
      (await repository.listSessions(catalogCourseId)).items.single.id,
      catalogSessionId,
    );
    expect(requests.last.url.path, '/rest/v1/rpc/list_catalog_sessions');
    expect(body(), {
      'p_course_id': catalogCourseId,
      'p_after_position': null,
      'p_after_id': null,
      'p_limit': 20,
    });
    response = catalogEnvelope([]);
    expect((await repository.listSessions(catalogCourseId)).items, isEmpty);
    response = catalogEnvelope([
      {...catalogSessionRow(), 'course_id': catalogOtherId},
    ]);
    await expectLater(
      repository.listSessions(catalogCourseId),
      throwsA(failure(CatalogFailureKind.invalidResponse)),
    );
  });
  test(
    'bad detail/outline IDs and invalid outline page settings do not transmit',
    () async {
      await expectLater(
        repository.getCourse('bad'),
        throwsA(failure(CatalogFailureKind.invalidInput)),
      );
      await expectLater(
        repository.listSessions('bad'),
        throwsA(failure(CatalogFailureKind.invalidInput)),
      );
      await expectLater(
        repository.listSessions(catalogCourseId, limit: 0),
        throwsA(failure(CatalogFailureKind.invalidInput)),
      );
      expect(requests, isEmpty);
    },
  );
  test(
    'filters have no search/page parameters and remain full-catalog options',
    () async {
      response = {
        'categories': ['Civil', 'Mechanical'],
        'levels': ['Advanced', 'Beginner'],
      };
      final filters = await repository.getFilters();
      expect(filters.categories, ['Civil', 'Mechanical']);
      expect(requests.single.url.path, '/rest/v1/rpc/get_catalog_filters');
      expect(body(), isEmpty);
    },
  );
  for (final operation in ['courses', 'course', 'sessions', 'filters']) {
    test(
      '$operation rejects delayed results after actor switch and pins origin token',
      () async {
        respondFor(operation);
        final token = client.auth.currentSession!.accessToken;
        pending = Completer<http.Response>();
        final future = read(operation);
        final assertion = expectLater(
          future,
          throwsA(failure(CatalogFailureKind.actorChanged)),
        );
        await Future<void>.delayed(Duration.zero);
        expect(requests, hasLength(1));
        final request = requests.single;
        await signInAs(catalogOtherActor);
        pending!.complete(
          http.Response(
            jsonEncode(response),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          ),
        );
        await assertion;
        expect(request.headers['authorization'], 'Bearer $token');
      },
    );
    test(
      '$operation requires a live nonexpired authenticated session before network',
      () async {
        await signInAs(catalogActor, lifetime: -100);
        await expectLater(
          read(operation),
          throwsA(failure(CatalogFailureKind.accessRequired)),
        );
        expect(requests, isEmpty);
      },
    );
    test(
      '$operation blocks never-authenticated and custom-token-only clients',
      () async {
        for (final custom in [false, true]) {
          final isolated = SupabaseClient(
            'https://example.test',
            'sb_publishable_test',
            accessToken: custom ? () async => 'PRIVATE_CANARY' : null,
            authOptions: const AuthClientOptions(autoRefreshToken: false),
            httpClient: MockClient(
              (_) async => throw StateError('Must not transmit'),
            ),
          );
          final original = repository;
          repository = SupabaseCatalogRepository(isolated);
          expect(repository.currentActorId, isNull);
          await expectLater(
            read(operation),
            throwsA(failure(CatalogFailureKind.accessRequired)),
          );
          repository = original;
          await isolated.dispose();
        }
      },
    );
  }
  test('A to B to A transition still invalidates pending result', () async {
    pending = Completer<http.Response>();
    final assertion = expectLater(
      repository.listCourses(),
      throwsA(failure(CatalogFailureKind.actorChanged)),
    );
    await Future<void>.delayed(Duration.zero);
    await signInAs(catalogOtherActor);
    await signInAs(catalogActor);
    pending!.complete(
      http.Response(
        jsonEncode(response),
        200,
        request: requests.single,
        headers: {'content-type': 'application/json'},
      ),
    );
    await assertion;
  });
  test('signout invalidates pending result and getter without returning catalog data', () async {
    pending = Completer<http.Response>();
    final assertion = expectLater(
      repository.listCourses(),
      throwsA(isA<CatalogFailure>()),
    );
    await Future<void>.delayed(Duration.zero);
    final request = requests.single;
    await client.auth.signOut(scope: SignOutScope.local);
    expect(repository.currentActorId, isNull);
    pending!.complete(
      http.Response(
        jsonEncode(response),
        200,
        request: request,
        headers: {'content-type': 'application/json'},
      ),
    );
    await assertion;
  });
  test('same actor token refresh does not invalidate delayed read', () async {
    pending = Completer<http.Response>();
    final future = repository.listCourses();
    await Future<void>.delayed(Duration.zero);
    await signInAs(catalogActor, lifetime: 7200);
    pending!.complete(
      http.Response(
        jsonEncode(response),
        200,
        request: requests.single,
        headers: {'content-type': 'application/json'},
      ),
    );
    expect((await future).items, hasLength(1));
  });
  for (final entry in [
    (42501, 'catalog_access_required', CatalogFailureKind.accessRequired),
    (22023, 'invalid_catalog_input', CatalogFailureKind.invalidInput),
    (42501, 'PRIVATE_CANARY', CatalogFailureKind.requestFailed),
  ]) {
    test(
      'server error ${entry.$1}/${entry.$2} maps to sanitized ${entry.$3}',
      () async {
        status = 400;
        response = {
          'code': '${entry.$1}',
          'message': entry.$2,
          'details': 'PRIVATE_CANARY',
          'hint': 'PRIVATE_CANARY',
        };
        await expectLater(repository.listCourses(), throwsA(failure(entry.$3)));
        expect(requests, hasLength(1));
      },
    );
  }
  test('network error sanitized with no retry or fallback', () async {
    networkError = StateError('PRIVATE_CANARY');
    await expectLater(
      repository.listCourses(),
      throwsA(failure(CatalogFailureKind.requestFailed)),
    );
    expect(requests, hasLength(1));
  });
  test('bounded timeout does not retry or accept late data', () async {
    repository = SupabaseCatalogRepository(
      client,
      timeout: const Duration(milliseconds: 20),
    );
    pending = Completer<http.Response>();
    await expectLater(
      repository.listCourses(),
      throwsA(failure(CatalogFailureKind.timedOut)),
    );
    expect(requests, hasLength(1));
    pending!.complete(
      http.Response(
        jsonEncode(response),
        200,
        request: requests.single,
        headers: {'content-type': 'application/json'},
      ),
    );
    pending = null;
    expect((await repository.listCourses()).items, hasLength(1));
    expect(requests, hasLength(2));
  });
  for (final bad in [
    null,
    {'items': [], 'has_more': false},
    {
      'items': [],
      'has_more': false,
      'next_cursor': null,
      'private_payload': 'PRIVATE_CANARY',
    },
  ]) {
    test('malformed page fails closed ${bad.runtimeType}', () async {
      response = bad;
      await expectLater(
        repository.listCourses(),
        throwsA(failure(CatalogFailureKind.invalidResponse)),
      );
    });
  }
}
