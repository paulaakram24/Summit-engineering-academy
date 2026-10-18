import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:summit_academy/auth/auth_repository.dart';
import 'package:summit_academy/auth/supabase_auth_repository.dart';

import 'auth_fakes.dart';

const userId = '22222222-2222-4222-8222-222222222222';
Map<String, dynamic> sessionJson() {
  String segment(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return {
    'access_token':
        '${segment({'alg': 'HS256'})}.${segment({'sub': userId, 'exp': 4102444800})}.synthetic',
    'refresh_token': 'synthetic-refresh',
    'token_type': 'bearer',
    'expires_in': 3600,
    'user': {
      'id': userId,
      'aud': 'authenticated',
      'role': 'authenticated',
      'email': 'learner@example.test',
      'app_metadata': <String, dynamic>{},
      'user_metadata': <String, dynamic>{},
      'created_at': '2026-01-01T00:00:00Z',
    },
  };
}

void main() {
  late SupabaseClient client;
  late SupabaseAuthRepository repo;
  final requests = <http.Request>[];
  var emptyUpdate = false;
  String? serverError;
  setUp(() async {
    requests.clear();
    emptyUpdate = false;
    serverError = null;
    client = SupabaseClient(
      'https://example.test',
      'sb_publishable_test_public',
      authOptions: const AuthClientOptions(autoRefreshToken: false),
      httpClient: MockClient((request) async {
        requests.add(request);
        http.Response response(String body, int status) => http.Response(
          body,
          status,
          request: request,
          headers: {'content-type': 'application/json'},
        );
        if (request.url.path.endsWith('/token')) {
          return response(jsonEncode(sessionJson()), 200);
        }
        if (serverError != null) {
          return response(
            jsonEncode({'message': serverError, 'code': '42501'}),
            403,
          );
        }
        if (request.url.path.endsWith('/get_access_context') ||
            request.url.path.endsWith('/register_device')) {
          return response(
            jsonEncode({
              'role': 'student',
              'device_id': '11111111-1111-4111-8111-111111111111',
            }),
            200,
          );
        }
        if (request.method == 'PATCH' && emptyUpdate) {
          return response(
            jsonEncode({'code': 'PGRST116', 'message': 'No rows'}),
            406,
          );
        }
        if (request.url.path.endsWith('/profiles')) {
          return response(
            jsonEncode({
              'id': userId,
              'name': 'Learner',
              'phone': '+201234567890',
              'university': 'Summit',
              'created_at': '2026-01-01T00:00:00Z',
            }),
            200,
          );
        }
        return response('{}', 200);
      }),
    );
    await client.auth.setInitialSession(jsonEncode(sessionJson()));
    repo = SupabaseAuthRepository(client, MemorySecrets(), 'sea.test');
  });
  tearDown(() async {
    await repo.dispose();
    await client.dispose();
  });
  test(
    'SDK password sign-in is classified as fresh authentication exactly once',
    () async {
      final events = <SessionEvent>[];
      final subscription = repo.events.listen(events.add);
      await repo.signIn('learner@example.test', 'synthetic-password');
      await Future<void>.delayed(Duration.zero);
      expect(events.where((event) => event == SessionEvent.signedIn).length, 1);
      await subscription.cancel();
    },
  );
  test('profile save validates active context then UPDATEs allowed columns and checks returned row', () async {
    await repo.saveProfile(
      const AccountProfile(
        name: 'Learner',
        phone: '+201234567890',
        university: 'Summit',
      ),
    );
    expect(requests.first.url.path, endsWith('/get_access_context'));
    final update = requests.last;
    expect(update.method, 'PATCH');
    expect(update.url.queryParameters['id'], 'eq.$userId');
    expect(update.url.queryParameters['select'], contains('id'));
    expect(jsonDecode(update.body), {
      'name': 'Learner',
      'phone': '+201234567890',
      'university': 'Summit',
    });
    expect(update.headers['Prefer'], contains('return=representation'));
    expect(
      requests.where(
        (r) => r.url.path.endsWith('/profiles') && r.method == 'POST',
      ),
      isEmpty,
    );
  });
  test('zero affected profile rows are a failure, never success', () async {
    emptyUpdate = true;
    await expectLater(
      repo.saveProfile(
        const AccountProfile(
          name: 'Learner',
          phone: '123456789',
          university: 'Summit',
        ),
      ),
      throwsA(isA<AccountFailure>()),
    );
  });
  test('device RPC sends stable 64hex installation secret and label', () async {
    await repo.registerDevice();
    await repo.registerDevice();
    final first = jsonDecode(requests.first.body) as Map;
    expect(first.keys, unorderedEquals(['p_device_token', 'p_label']));
    expect(first['p_device_token'], matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(
      jsonDecode(requests.last.body)['p_device_token'],
      first['p_device_token'],
    );
  });
  test('signout explicitly scopes revocation locally', () async {
    await repo.signOut();
    final logout = requests.singleWhere(
      (request) => request.url.path.endsWith('/logout'),
    );
    expect(logout.url.queryParameters['scope'], 'local');
    expect(
      requests.where((request) => request.url.path.endsWith('/end_session')),
      isEmpty,
    );
  });
  for (final code in [
    'active_session_exists',
    'device_limit',
    'session_not_registered',
    'session_replaced',
    'unverified_or_invalid_session',
    'account_disabled',
    'device_revoked',
    'session_device_mismatch',
  ]) {
    test('maps backend $code without exposing server text', () async {
      serverError = code;
      await expectLater(
        repo.getAccessContext(),
        throwsA(isA<AccountFailure>().having((e) => e.code, 'code', code)),
      );
    });
  }
}
