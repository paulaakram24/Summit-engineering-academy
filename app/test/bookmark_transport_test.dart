import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:summit_academy/bookmarks/bookmark_repository.dart';
import 'package:summit_academy/bookmarks/supabase_bookmark_repository.dart';

import 'catalog_models_test.dart'
    show
        catalogActor,
        catalogOtherActor,
        catalogCourseId,
        catalogOtherId,
        catalogCourseRow,
        catalogEnvelope;

void main() {
  late SupabaseClient client;
  late SupabaseBookmarkRepository repository;
  late List<http.Request> requests;
  Object? response;
  var status = 200;
  Completer<http.Response>? pending;
  Object? networkError;
  Future<void> signIn(
    String actor, {
    int lifetime = 3600,
  }) => client.auth.setInitialSession(
    jsonEncode({
      'access_token':
          '${base64Url.encode(utf8.encode('{"alg":"HS256"}')).replaceAll('=', '')}.${base64Url.encode(utf8.encode(jsonEncode({'sub': actor, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + lifetime}))).replaceAll('=', '')}.synthetic-signature',
      'token_type': 'bearer',
      'refresh_token': 'synthetic-refresh',
      'user': {
        'id': actor,
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-10-20T00:00:00Z',
      },
    }),
  );
  Map<String, dynamic> state(bool saved, {int revision = 1}) => {
    'course_id': catalogCourseId,
    'saved': saved,
    'revision': revision,
  };
  Matcher failure(BookmarkFailureKind kind) => isA<BookmarkFailure>()
      .having((e) => e.kind, 'kind', kind)
      .having(
        (e) => e.toString(),
        'sanitized',
        isNot(contains('PRIVATE_CANARY')),
      );
  SetCourseBookmarkRequest intent({
    String actor = catalogActor,
    bool saved = true,
    int revision = 0,
  }) => SetCourseBookmarkRequest(
    actorId: actor,
    courseId: catalogCourseId,
    saved: saved,
    expectedRevision: revision,
  );
  setUp(() async {
    requests = [];
    response = state(true);
    status = 200;
    pending = null;
    networkError = null;
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
    repository = SupabaseBookmarkRepository(client);
    await signIn(catalogActor);
  });
  tearDown(() => client.dispose());
  Map<String, dynamic> body() =>
      jsonDecode(requests.last.body) as Map<String, dynamic>;
  Future<Object?> call(String action) => switch (action) {
    'get' => repository.getBookmark(catalogCourseId),
    'set' => repository.setBookmark(intent()),
    _ => repository.listSavedCourses(),
  };
  void respondFor(String action) {
    response = action == 'list'
        ? catalogEnvelope([catalogCourseRow()])
        : state(true);
  }

  test(
    'state read exact parameters, nullable unavailable, no metadata fallback',
    () async {
      expect((await repository.getBookmark(catalogCourseId))!.saved, isTrue);
      expect(requests.single.url.path, '/rest/v1/rpc/get_course_bookmark');
      expect(body(), {'p_course_id': catalogCourseId});
      response = null;
      expect(await repository.getBookmark(catalogCourseId), isNull);
      expect(requests, hasLength(2));
    },
  );
  test('explicit true and false transmit no actor field, duplicate state remains exact', () async {
    var revision = 0;
    for (final saved in [true, true, false, false]) {
      response = state(saved, revision: revision + 1);
      expect(
        (await repository.setBookmark(intent(saved: saved, revision: revision)))
            .saved,
        saved,
      );
      expect(body(), {
        'p_course_id': catalogCourseId,
        'p_saved': saved,
        'p_expected_revision': revision,
      });
      revision++;
      expect(requests.last.url.path, '/rest/v1/rpc/set_course_bookmark');
    }
  });
  test('default page20, max50 and paired cursor use existing strict safe projection', () async {
    response = catalogEnvelope([catalogCourseRow()]);
    expect(
      (await repository.listSavedCourses()).items.single.pricePiasters,
      10001,
    );
    expect(requests.last.url.path, '/rest/v1/rpc/list_saved_courses');
    expect(body(), {
      'p_after_position': null,
      'p_after_id': null,
      'p_limit': 20,
    });
    response = catalogEnvelope([
      catalogCourseRow(id: catalogOtherId, position: 2),
    ]);
    await repository.listSavedCourses(
      after: const CatalogCursor(position: 1, id: catalogCourseId),
      limit: 50,
    );
    expect(body(), {
      'p_after_position': 1,
      'p_after_id': catalogCourseId,
      'p_limit': 50,
    });
  });
  for (final scenario in [
    'extra',
    'duplicate',
    'nonadvancing',
    'wrong-cursor',
    'oversized',
  ]) {
    test(
      'strict catalog page violations map to bookmark failure $scenario',
      () async {
        CatalogCursor? after;
        var limit = 20;
        response = catalogEnvelope([catalogCourseRow()]);
        switch (scenario) {
          case 'extra':
            response = catalogEnvelope([
              {...catalogCourseRow(), 'created_by': 'PRIVATE_CANARY'},
            ]);
          case 'duplicate':
            response = catalogEnvelope([
              catalogCourseRow(),
              catalogCourseRow(),
            ]);
          case 'nonadvancing':
            after = const CatalogCursor(position: 0, id: catalogCourseId);
          case 'wrong-cursor':
            response = {
              ...catalogEnvelope([catalogCourseRow()]),
              'next_cursor': {'position': 1, 'id': catalogCourseId},
            };
          case 'oversized':
            limit = 1;
            response = catalogEnvelope([
              catalogCourseRow(),
              catalogCourseRow(id: catalogOtherId),
            ]);
        }
        await expectLater(
          repository.listSavedCourses(after: after, limit: limit),
          throwsA(failure(BookmarkFailureKind.invalidResponse)),
        );
      },
    );
  }
  for (final bad in [
    null,
    {...state(true), 'course_id': catalogOtherId},
    {...state(true), 'saved': false},
    {...state(true), 'saved': 'true'},
    {...state(true), 'course_id': 'bad'},
    {...state(true), 'private': 'PRIVATE_CANARY'},
  ]) {
    test(
      'mutation validates exact entity, shape and desired state $bad',
      () async {
        response = bad;
        await expectLater(
          repository.setBookmark(intent()),
          throwsA(failure(BookmarkFailureKind.invalidResponse)),
        );
      },
    );
  }
  test('invalid IDs, actor, cursor and limits fail before network', () async {
    await expectLater(
      repository.getBookmark('bad'),
      throwsA(failure(BookmarkFailureKind.invalidInput)),
    );
    await expectLater(
      repository.setBookmark(intent(actor: 'bad')),
      throwsA(failure(BookmarkFailureKind.invalidInput)),
    );
    for (final limit in [0, 51]) {
      await expectLater(
        repository.listSavedCourses(limit: limit),
        throwsA(failure(BookmarkFailureKind.invalidInput)),
      );
    }
    await expectLater(
      repository.listSavedCourses(
        after: const CatalogCursor(position: -1, id: catalogCourseId),
      ),
      throwsA(failure(BookmarkFailureKind.invalidInput)),
    );
    expect(requests, isEmpty);
  });
  test('retained mutation rejects different actor before transmission, same actor remains exact', () async {
    final request = intent();
    await signIn(catalogOtherActor);
    await expectLater(
      repository.setBookmark(request),
      throwsA(failure(BookmarkFailureKind.actorChanged)),
    );
    expect(requests, isEmpty);
    await signIn(catalogActor);
    await repository.setBookmark(request);
    expect(body()['p_saved'], isTrue);
  });
  for (final action in ['get', 'set', 'list']) {
    test(
      '$action pins captured JWT and rejects late actor switch including A-B-A',
      () async {
        respondFor(action);
        final token = client.auth.currentSession!.accessToken;
        pending = Completer<http.Response>();
        final assertion = expectLater(
          call(action),
          throwsA(failure(BookmarkFailureKind.actorChanged)),
        );
        await Future<void>.delayed(Duration.zero);
        final request = requests.single;
        await signIn(catalogOtherActor);
        await signIn(catalogActor);
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
        expect(client.headers['Authorization'], isNot('Bearer $token'));
      },
    );
    test(
      '$action blocks expired and absent session before any network',
      () async {
        await signIn(catalogActor, lifetime: -100);
        await expectLater(
          call(action),
          throwsA(failure(BookmarkFailureKind.accessRequired)),
        );
        expect(requests, isEmpty);
        await client.auth.signOut(scope: SignOutScope.local);
        requests.clear();
        expect(repository.currentActorId, isNull);
        await expectLater(
          call(action),
          throwsA(failure(BookmarkFailureKind.accessRequired)),
        );
        expect(requests, isEmpty);
      },
    );
  }
  test(
    'custom-token-only client cannot impersonate admitted identity',
    () async {
      final custom = SupabaseClient(
        'https://example.test',
        'sb_publishable_test',
        accessToken: () async => 'PRIVATE_CANARY',
        httpClient: MockClient(
          (_) async => throw StateError('Must not transmit'),
        ),
      );
      addTearDown(custom.dispose);
      final isolated = SupabaseBookmarkRepository(custom);
      expect(isolated.currentActorId, isNull);
      await expectLater(
        isolated.getBookmark(catalogCourseId),
        throwsA(failure(BookmarkFailureKind.accessRequired)),
      );
    },
  );
  test('same actor token refresh allows pending state without changing request header', () async {
    pending = Completer<http.Response>();
    final future = repository.getBookmark(catalogCourseId);
    await Future<void>.delayed(Duration.zero);
    await signIn(catalogActor, lifetime: 7200);
    pending!.complete(
      http.Response(
        jsonEncode(response),
        200,
        request: requests.single,
        headers: {'content-type': 'application/json'},
      ),
    );
    expect((await future)!.saved, isTrue);
  });
  for (final error in [
    ('42501', 'bookmark_access_required', BookmarkFailureKind.accessRequired),
    (
      '42501',
      'bookmark_course_unavailable',
      BookmarkFailureKind.courseUnavailable,
    ),
    ('22023', 'invalid_bookmark_input', BookmarkFailureKind.invalidInput),
    ('42501', 'PRIVATE_CANARY', BookmarkFailureKind.requestFailed),
  ]) {
    test('sanitized server error mapping ${error.$2}', () async {
      status = 400;
      response = {
        'code': error.$1,
        'message': error.$2,
        'details': 'PRIVATE_CANARY',
        'hint': 'PRIVATE_CANARY',
      };
      await expectLater(
        repository.setBookmark(intent()),
        throwsA(failure(error.$3)),
      );
      expect(requests, hasLength(1));
    });
  }
  test('mutation timeout never auto retries; subsequent explicit read reconciles state', () async {
    repository = SupabaseBookmarkRepository(
      client,
      timeout: const Duration(milliseconds: 20),
    );
    pending = Completer<http.Response>();
    await expectLater(
      repository.setBookmark(intent()),
      throwsA(failure(BookmarkFailureKind.timedOut)),
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
    expect((await repository.getBookmark(catalogCourseId))!.saved, isTrue);
    expect(requests, hasLength(2));
  });
  test(
    'stale expected revision is conflict, never an automatic mutation retry',
    () async {
      status = 403;
      response = {
        'code': '42501',
        'message': 'bookmark_state_conflict',
        'details': 'PRIVATE_CANARY',
      };
      await expectLater(
        repository.setBookmark(intent(revision: 4)),
        throwsA(failure(BookmarkFailureKind.stateConflict)),
      );
      expect(body()['p_expected_revision'], 4);
      expect(requests, hasLength(1));
      status = 200;
      response = state(false, revision: 6);
      expect((await repository.getBookmark(catalogCourseId))!.revision, 6);
      expect(
        requests.where((r) => r.url.path.endsWith('set_course_bookmark')),
        hasLength(1),
      );
    },
  );
  test('mutation requires exactly next revision; malformed or stale responses fail closed', () async {
    for (final revision in [null, -1, 2147483648, '1', 1.0, 0, 2]) {
      response = {...state(true), 'revision': revision};
      await expectLater(
        repository.setBookmark(intent()),
        throwsA(failure(BookmarkFailureKind.invalidResponse)),
      );
    }
    for (final revision in [-1, 2147483647]) {
      final count = requests.length;
      await expectLater(
        repository.setBookmark(intent(revision: revision)),
        throwsA(failure(BookmarkFailureKind.invalidInput)),
      );
      expect(requests, hasLength(count));
    }
  });
  test(
    'acknowledgement must be exactly expected plus one, not same or jumped',
    () async {
      for (final revision in [4, 6]) {
        response = state(true, revision: revision);
        await expectLater(
          repository.setBookmark(intent(revision: 4)),
          throwsA(failure(BookmarkFailureKind.invalidResponse)),
        );
      }
      response = state(true, revision: 5);
      expect((await repository.setBookmark(intent(revision: 4))).revision, 5);
    },
  );
  test('unexpected errors do not expose raw bodies or retry', () async {
    networkError = StateError('PRIVATE_CANARY');
    await expectLater(
      repository.getBookmark(catalogCourseId),
      throwsA(failure(BookmarkFailureKind.requestFailed)),
    );
    expect(requests, hasLength(1));
  });
}
