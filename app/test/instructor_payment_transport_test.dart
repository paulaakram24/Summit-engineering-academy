import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:summit_academy/commerce/instructor_payment_repository.dart';
import 'package:summit_academy/commerce/supabase_instructor_payment_repository.dart';

const actor = '11111111-1111-4111-8111-111111111111';
const other = '22222222-2222-4222-8222-222222222222';
const course = '33333333-3333-4333-8333-333333333333';

void main() {
  late SupabaseClient client;
  late SupabaseInstructorPaymentRepository repository;
  late List<http.Request> requests;
  Object? response;
  String? raw;
  var status = 200;
  Completer<http.Response>? pending;
  Map<String, Object?> profile() => {
    'instructor_id': actor,
    'recipient_name': 'Synthetic Recipient',
    'phone_number': '+201234567890',
    'method_configuration': 'instapay_only',
    'revision': 1,
  };
  Map<String, Object?> binding() => {
    'course_id': course,
    'instructor_id': other,
    'revision': 1,
  };
  Future<void> signIn(String id) => client.auth.setInitialSession(
    jsonEncode({
      'access_token':
          '${base64Url.encode(utf8.encode('{"alg":"HS256"}')).replaceAll('=', '')}.${base64Url.encode(utf8.encode(jsonEncode({'sub': id, 'exp': DateTime.now().millisecondsSinceEpoch ~/ 1000 + 3600}))).replaceAll('=', '')}.synthetic',
      'token_type': 'bearer',
      'refresh_token': 'synthetic-refresh',
      'user': {
        'id': id,
        'app_metadata': {},
        'user_metadata': {},
        'aud': 'authenticated',
        'created_at': '2026-10-21T00:00:00Z',
      },
    }),
  );
  setUp(() async {
    requests = [];
    status = 200;
    raw = null;
    pending = null;
    response = profile();
    client = SupabaseClient(
      'https://example.test',
      'sb_publishable_test',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        if (pending != null && request.url.path.startsWith('/rest/')) {
          return pending!.future;
        }
        return http.Response(
          raw ?? jsonEncode(response),
          status,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    repository = SupabaseInstructorPaymentRepository(client);
    await signIn(actor);
  });
  tearDown(() => client.dispose());
  Matcher failure(InstructorPaymentFailureKind kind) =>
      isA<InstructorPaymentFailure>()
          .having((e) => e.kind, 'kind', kind)
          .having(
            (e) => e.toString(),
            'sanitized',
            isNot(contains('PRIVATE_CANARY')),
          );
  SaveInstructorPaymentProfileRequest save({int revision = 0}) =>
      SaveInstructorPaymentProfileRequest(
        actorId: actor,
        recipientName: ' Synthetic Recipient ',
        phoneNumber: '+201234567890',
        methodConfiguration: InstructorPaymentMethodConfiguration.instapayOnly,
        expectedRevision: revision,
      );
  SetCoursePaymentInstructorRequest assign() =>
      SetCoursePaymentInstructorRequest(
        actorId: actor,
        courseId: course,
        instructorId: other,
        expectedRevision: 0,
      );
  Map<String, dynamic> body() =>
      jsonDecode(requests.last.body) as Map<String, dynamic>;
  Future<Object?> action(String name) => switch (name) {
    'profile' => repository.getMyProfile(actorId: actor),
    'save' => repository.saveMyProfile(save()),
    'binding' => repository.getCourseInstructor(
      actorId: actor,
      courseId: course,
    ),
    'assign' => repository.setCourseInstructor(assign()),
    _ => repository.listInstructors(actorId: actor),
  };
  void prepare(String name) {
    response = switch (name) {
      'profile' || 'save' => profile(),
      'binding' || 'assign' => binding(),
      _ => {'items': [], 'has_more': false, 'next_cursor': null},
    };
  }

  test(
    'own profile pins initiating JWT and sends no ownership parameters',
    () async {
      final token = client.auth.currentSession!.accessToken;
      expect(
        (await repository.getMyProfile(actorId: actor))!.instructorId,
        actor,
      );
      expect(
        requests.single.url.path,
        '/rest/v1/rpc/get_my_instructor_payment_profile',
      );
      expect(body(), isEmpty);
      expect(requests.single.headers['authorization'], 'Bearer $token');
      expect(client.headers['Authorization'], isNot('Bearer $token'));
    },
  );
  test('unconfigured profile and course remain null', () async {
    response = null;
    expect(await repository.getMyProfile(actorId: actor), isNull);
    expect(
      await repository.getCourseInstructor(actorId: actor, courseId: course),
      isNull,
    );
  });
  test('save sends only normalized profile and expected revision', () async {
    await repository.saveMyProfile(save());
    expect(
      requests.single.url.path,
      '/rest/v1/rpc/save_my_instructor_payment_profile',
    );
    expect(body(), {
      'p_recipient_name': 'Synthetic Recipient',
      'p_phone_number': '+201234567890',
      'p_method_configuration': 'instapay_only',
      'p_expected_revision': 0,
    });
  });
  test('course read uses exact course, not actor', () async {
    response = binding();
    await repository.getCourseInstructor(actorId: actor, courseId: course);
    expect(
      requests.single.url.path,
      '/rest/v1/rpc/get_course_payment_instructor',
    );
    expect(body(), {'p_course_id': course});
  });
  test('assignment uses explicit account UUID and CAS', () async {
    response = binding();
    await repository.setCourseInstructor(assign());
    expect(
      requests.single.url.path,
      '/rest/v1/rpc/set_course_payment_instructor',
    );
    expect(body(), {
      'p_course_id': course,
      'p_instructor_id': other,
      'p_expected_revision': 0,
    });
  });
  test('directory default cursor and maximum limit remain bounded', () async {
    prepare('list');
    await repository.listInstructors(actorId: actor);
    expect(body(), {'p_after_id': null, 'p_limit': 20});
    await repository.listInstructors(
      actorId: actor,
      after: PaymentInstructorCursor(instructorId: other),
      limit: 50,
    );
    expect(body(), {'p_after_id': other, 'p_limit': 50});
    expect(requests.last.url.path, '/rest/v1/rpc/list_payment_instructors');
  });
  for (final name in ['profile', 'save', 'binding', 'assign', 'list']) {
    test('$name rejects A-B-A change and makes only one request', () async {
      prepare(name);
      pending = Completer<http.Response>();
      final future = action(name);
      final assertion = expectLater(
        future,
        throwsA(failure(InstructorPaymentFailureKind.actorChanged)),
      );
      await Future<void>.delayed(Duration.zero);
      await signIn(other);
      await signIn(actor);
      await Future<void>.delayed(Duration.zero);
      pending!.complete(
        http.Response(
          jsonEncode(response),
          200,
          request: requests.first,
          headers: {'content-type': 'application/json'},
        ),
      );
      await assertion;
      expect(requests, hasLength(1));
    });
    test('$name sanitizes unknown backend detail without retry', () async {
      prepare(name);
      status = 400;
      response = {
        'code': '42501',
        'message': 'PRIVATE_CANARY',
        'details': 'PRIVATE_CANARY',
      };
      await expectLater(
        action(name),
        throwsA(failure(InstructorPaymentFailureKind.requestFailed)),
      );
      expect(requests, hasLength(1));
    });
    test('$name timeout never retries mutation or read', () async {
      prepare(name);
      pending = Completer<http.Response>();
      repository = SupabaseInstructorPaymentRepository(
        client,
        timeout: const Duration(milliseconds: 10),
      );
      await expectLater(
        action(name),
        throwsA(failure(InstructorPaymentFailureKind.timedOut)),
      );
      pending!.complete(http.Response(jsonEncode(response), 200));
      await Future<void>.delayed(Duration.zero);
      expect(requests, hasLength(1));
    });
  }
  for (final pair in [
    (
      '42501',
      'payment_setup_access_required',
      InstructorPaymentFailureKind.accessRequired,
    ),
    (
      '42501',
      'payment_setup_target_unavailable',
      InstructorPaymentFailureKind.targetUnavailable,
    ),
    (
      '42501',
      'payment_setup_state_conflict',
      InstructorPaymentFailureKind.stateConflict,
    ),
    (
      '22023',
      'invalid_payment_setup_input',
      InstructorPaymentFailureKind.invalidInput,
    ),
  ]) {
    test('maps exact ${pair.$2} without raw diagnostics', () async {
      status = 400;
      response = {
        'code': pair.$1,
        'message': pair.$2,
        'details': 'PRIVATE_CANARY',
      };
      await expectLater(
        repository.saveMyProfile(save()),
        throwsA(failure(pair.$3)),
      );
    });
  }
  for (final entry in <String, Object?>{
    'instructor_id': other,
    'recipient_name': 'Wrong recipient',
    'phone_number': '+201111111111',
    'method_configuration': 'instapay_and_vodafone_cash',
    'revision': 2,
    'bank_name': 'PRIVATE_CANARY',
  }.entries) {
    test('save rejects mismatching/extra ${entry.key}', () async {
      response = {...profile(), entry.key: entry.value};
      await expectLater(
        repository.saveMyProfile(save()),
        throwsA(failure(InstructorPaymentFailureKind.invalidResponse)),
      );
    });
  }
  for (final entry in <String, Object?>{
    'course_id': actor,
    'instructor_id': actor,
    'revision': 2,
  }.entries) {
    test('assignment rejects wrong ${entry.key}', () async {
      response = {...binding(), entry.key: entry.value};
      await expectLater(
        repository.setCourseInstructor(assign()),
        throwsA(failure(InstructorPaymentFailureKind.invalidResponse)),
      );
    });
  }
  test('read rejects wrong own-profile and course identities', () async {
    response = {...profile(), 'instructor_id': other};
    await expectLater(
      action('profile'),
      throwsA(failure(InstructorPaymentFailureKind.invalidResponse)),
    );
    response = {...binding(), 'course_id': actor};
    await expectLater(
      action('binding'),
      throwsA(failure(InstructorPaymentFailureKind.invalidResponse)),
    );
  });
  test('invalid actor, course and limits make zero HTTP requests', () async {
    await expectLater(
      repository.getMyProfile(actorId: 'bad'),
      throwsA(failure(InstructorPaymentFailureKind.invalidInput)),
    );
    await expectLater(
      repository.getCourseInstructor(actorId: actor, courseId: 'bad'),
      throwsA(failure(InstructorPaymentFailureKind.invalidInput)),
    );
    for (final limit in [0, 51]) {
      await expectLater(
        repository.listInstructors(actorId: actor, limit: limit),
        throwsA(failure(InstructorPaymentFailureKind.invalidInput)),
      );
    }
    expect(requests, isEmpty);
  });
  test('wrong initiating actor rejected before network', () async {
    await expectLater(
      repository.getMyProfile(actorId: other),
      throwsA(failure(InstructorPaymentFailureKind.actorChanged)),
    );
    expect(requests, isEmpty);
  });
  test('signed-out setup is denied locally without an HTTP call', () async {
    await client.auth.signOut(scope: SignOutScope.local);
    requests.clear();
    await expectLater(
      repository.getMyProfile(actorId: actor),
      throwsA(failure(InstructorPaymentFailureKind.accessRequired)),
    );
    expect(requests, isEmpty);
  });
  test(
    'same-actor session event keeps the pinned in-flight read valid',
    () async {
      pending = Completer<http.Response>();
      final token = client.auth.currentSession!.accessToken;
      final future = repository.getMyProfile(actorId: actor);
      await Future<void>.delayed(Duration.zero);
      await signIn(actor);
      pending!.complete(
        http.Response(
          jsonEncode(profile()),
          200,
          request: requests.first,
          headers: {'content-type': 'application/json'},
        ),
      );
      expect((await future)!.instructorId, actor);
      expect(requests.single.headers['authorization'], 'Bearer $token');
    },
  );
  test('sign-out while a write is pending rejects its late response', () async {
    pending = Completer<http.Response>();
    final future = repository.saveMyProfile(save());
    final assertion = expectLater(
      future,
      throwsA(failure(InstructorPaymentFailureKind.actorChanged)),
    );
    await Future<void>.delayed(Duration.zero);
    await client.auth.signOut(scope: SignOutScope.local);
    await Future<void>.delayed(Duration.zero);
    pending!.complete(
      http.Response(
        jsonEncode(profile()),
        200,
        request: requests.first,
        headers: {'content-type': 'application/json'},
      ),
    );
    await assertion;
    expect(
      requests.where((r) => r.url.path.startsWith('/rest/')),
      hasLength(1),
    );
  });
  test('invalid request factories cannot create a write', () {
    expect(
      () => save(revision: -1),
      throwsA(failure(InstructorPaymentFailureKind.invalidInput)),
    );
    expect(
      () => save(revision: instructorPaymentMaxRevision),
      throwsA(failure(InstructorPaymentFailureKind.invalidInput)),
    );
    expect(
      () => SetCoursePaymentInstructorRequest(
        actorId: actor,
        courseId: 'bad',
        instructorId: other,
        expectedRevision: 0,
      ),
      throwsA(failure(InstructorPaymentFailureKind.invalidInput)),
    );
    expect(requests, isEmpty);
  });
  test('malformed JSON and private directory fields are rejected', () async {
    raw = '{PRIVATE_CANARY';
    // PostgREST wraps a malformed JSON body as its own unknown-code exception.
    await expectLater(
      action('profile'),
      throwsA(failure(InstructorPaymentFailureKind.requestFailed)),
    );
    raw = null;
    response = {
      'items': [
        {
          'instructor_id': other,
          'display_name': 'Synthetic',
          'phone_number': 'PRIVATE_CANARY',
        },
      ],
      'has_more': false,
      'next_cursor': null,
    };
    await expectLater(
      action('list'),
      throwsA(failure(InstructorPaymentFailureKind.invalidResponse)),
    );
  });
}
