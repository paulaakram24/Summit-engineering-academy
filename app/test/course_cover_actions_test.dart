import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:summit_academy/content/course_cover_actions.dart';
import 'package:summit_academy/content/course_covers.dart';

import 'course_cover_panel_test.dart' as fixture;

void main() {
  test(
    'removal uses deployed nullable CAS RPC and never deletes storage',
    () async {
      final requests = <http.Request>[];
      final original = fixture.course();
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        accessToken: () async => 'synthetic-user-jwt',
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response(
            jsonEncode({
              ...original.toDraft().toJson(),
              'id': original.id,
              'cover_path': null,
            }),
            200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      final result = await SupabaseCourseCoverActions(client).remove(original);
      expect(result.coverPath, isNull);
      expect(requests, hasLength(1));
      expect(requests.single.url.path, '/rest/v1/rpc/attach_course_cover');
      expect(jsonDecode(requests.single.body), {
        'p_course_id': original.id,
        'p_path': null,
        'p_expected_previous_path': original.coverPath,
      });
    },
  );
  for (final invalid in [
    'wrong-id',
    'deleted',
    'still-attached',
    'malformed',
    'conflict',
  ]) {
    test('removal rejects $invalid response with sanitized failure', () async {
      final original = fixture.course();
      final client = SupabaseClient(
        'https://example.supabase.co',
        'test-key',
        accessToken: () async => 'synthetic-user-jwt',
        httpClient: MockClient((request) async {
          final row = {
            ...original.toDraft().toJson(),
            'id': original.id,
            'cover_path': null,
          };
          if (invalid == 'wrong-id') row['id'] = 'other';
          if (invalid == 'deleted') {
            row['deleted_at'] = DateTime.utc(2026).toIso8601String();
          }
          if (invalid == 'still-attached') {
            row['cover_path'] = original.coverPath;
          }
          return http.Response(
            jsonEncode(
              invalid == 'conflict'
                  ? {'code': '40001', 'message': 'secret cover_changed token'}
                  : invalid == 'malformed'
                  ? []
                  : row,
            ),
            invalid == 'conflict' ? 409 : 200,
            request: request,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.dispose);
      await expectLater(
        SupabaseCourseCoverActions(client).remove(original),
        throwsA(isA<CourseCoverFailure>()),
      );
    });
  }
  test('deleted and coverless courses never send removal requests', () async {
    var calls = 0;
    final client = SupabaseClient(
      'https://example.supabase.co',
      'test-key',
      accessToken: () async => 'synthetic-user-jwt',
      httpClient: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    addTearDown(client.dispose);
    final actions = SupabaseCourseCoverActions(client);
    await expectLater(
      actions.remove(fixture.course(deleted: true)),
      throwsA(isA<CourseCoverFailure>()),
    );
    await expectLater(
      actions.remove(fixture.course(path: null)),
      throwsA(isA<CourseCoverFailure>()),
    );
    expect(calls, 0);
  });
}
