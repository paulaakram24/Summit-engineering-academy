import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:summit_academy/content/content_repository.dart';
import 'package:summit_academy/content/supabase_content_repository.dart';

const courseId = '11111111-1111-4111-8111-111111111111';
const sessionId = '22222222-2222-4222-8222-222222222222';
const draft = CourseDraft(
  title: ' Course ',
  instructor: ' Teacher ',
  category: ' Engineering ',
  level: ' Beginner ',
  pricePiasters: 12345,
);
const sessionDraft = SessionDraft(
  sessionNumber: 2,
  title: 'Session',
  pricePiasters: 123,
  isFreePreview: true,
);

Map<String, dynamic> courseRow() => {
  ...draft.toJson(),
  'id': courseId,
  'cover_path': null,
  'deleted_at': null,
  'created_by': courseId,
  'created_at': '2026-10-18T10:00:00Z',
  'updated_at': '2026-10-18T10:00:00Z',
};
Map<String, dynamic> sessionRow() => {
  ...sessionDraft.toJson(),
  'id': sessionId,
  'course_id': courseId,
  'deleted_at': null,
  'created_by': courseId,
  'created_at': '2026-10-18T10:00:00Z',
  'updated_at': '2026-10-18T10:00:00Z',
};

void main() {
  group('money and model contract', () {
    test('decimal EGP conversion is exact including maximum', () {
      for (final entry in {
        '0': 0,
        '0.01': 1,
        '12.3': 1230,
        '12.34': 1234,
        ' 21474836.47 ': maxContentInteger,
      }.entries) {
        expect(parsePricePiasters(entry.key), entry.value);
        expect(
          parsePricePiasters(formatPricePiasters(entry.value)),
          entry.value,
        );
      }
      for (final invalid in [
        '',
        '-1',
        '+1',
        '1e2',
        '1,000',
        '.5',
        '1.',
        '1.001',
        'NaN',
        '21474836.48',
        '99999999999999999999',
      ]) {
        expect(parsePricePiasters(invalid), isNull, reason: invalid);
      }
    });
    test('models decode server fields and draft payloads omit them', () {
      final course = Course.fromJson(courseRow());
      expect(course.title, 'Course');
      expect(course.createdAt, DateTime.utc(2026, 10, 18, 10));
      expect(course.toDraft().toJson(), draft.toJson());
      expect(
        course.toDraft().toJson().keys,
        unorderedEquals([
          'title',
          'description',
          'instructor',
          'category',
          'level',
          'price_piasters',
          'position',
          'status',
        ]),
      );
      final session = CourseSession.fromJson(sessionRow());
      expect(session.courseId, courseId);
      expect(session.isFreePreview, isTrue);
      expect(session.toDraft().toJson(), sessionDraft.toJson());
      expect(session.toDraft().toJson(), isNot(contains('course_id')));
      final deleted = Course.fromJson({
        ...courseRow(),
        'deleted_at': '2026-10-18T11:00:00Z',
        'status': 'archived',
      });
      expect(deleted.isDeleted, isTrue);
      expect(deleted.status, ContentStatus.archived);
    });
    test(
      'draft validators enforce required text, lengths and integer bounds',
      () {
        expect(draft.validationMessage, isNull);
        expect(validateContentText('😀' * 160, 'Title', 160), isNull);
        expect(validateContentText('x' * 161, 'Title', 160), isNotNull);
        expect(validateContentText(' ', 'Title', 160), isNotNull);
        expect(
          validateContentText(
            'x' * 10001,
            'Description',
            10000,
            required: false,
          ),
          isNotNull,
        );
        expect(
          const CourseDraft(
            title: '',
            instructor: 'T',
            category: 'C',
            level: 'L',
            pricePiasters: 0,
          ).validationMessage,
          isNotNull,
        );
        expect(
          const CourseDraft(
            title: 'T',
            instructor: 'T',
            category: 'C',
            level: 'L',
            pricePiasters: -1,
          ).validationMessage,
          isNotNull,
        );
        expect(
          const SessionDraft(
            sessionNumber: 0,
            title: 'T',
            pricePiasters: 0,
          ).validationMessage,
          isNotNull,
        );
        expect(
          const SessionDraft(
            sessionNumber: 1,
            title: 'T',
            pricePiasters: 0,
            position: 2147483648,
          ).validationMessage,
          isNotNull,
        );
        for (final invalid in ['-1', '1.2', '2147483648', '']) {
          expect(validateContentInteger(invalid), isNotNull);
        }
        expect(validateContentInteger('0', positive: true), isNotNull);
        expect(validateContentInteger('2147483647'), isNull);
      },
    );
  });

  group('Supabase requests', () {
    late SupabaseClient client;
    late SupabaseContentRepository repository;
    late List<http.Request> requests;
    int responseStatus = 200;
    Object? responseOverride;
    setUp(() {
      requests = [];
      responseStatus = 200;
      responseOverride = null;
      client = SupabaseClient(
        'https://example.test',
        'sb_publishable_test',
        authOptions: const AuthClientOptions(autoRefreshToken: false),
        httpClient: MockClient((request) async {
          requests.add(request);
          final row = request.url.path.endsWith('course_sessions')
              ? sessionRow()
              : courseRow();
          return http.Response(
            jsonEncode(
              responseOverride ?? (request.method == 'GET' ? [row] : row),
            ),
            responseStatus,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      repository = SupabaseContentRepository(client);
    });
    tearDown(() async {
      await client.dispose();
    });

    test(
      'courses use 20-row ordered ranges and exclude deleted by default',
      () async {
        expect(await repository.listCourses(offset: 20), hasLength(1));
        final query = requests.single.url.queryParameters;
        expect(query['offset'], '20');
        expect(query['limit'], '20');
        expect(query['order'], 'position.asc.nullslast,id.asc.nullslast');
        expect(query['deleted_at'], 'is.null');
        await repository.listCourses(includeDeleted: true);
        expect(
          requests.last.url.queryParameters,
          isNot(contains('deleted_at')),
        );
      },
    );
    test('sessions scope course, pagination and deleted filter', () async {
      final sessions = await repository.listSessions(courseId, offset: 40);
      expect(sessions.single.id, sessionId);
      final query = requests.single.url.queryParameters;
      expect(query['course_id'], 'eq.$courseId');
      expect(query['offset'], '40');
      expect(query['limit'], '20');
      expect(
        query['order'],
        'position.asc.nullslast,session_number.asc.nullslast,id.asc.nullslast',
      );
      expect(query['deleted_at'], 'is.null');
      await repository.listSessions(courseId, includeDeleted: true);
      expect(requests.last.url.queryParameters, isNot(contains('deleted_at')));
    });
    test(
      'course insert and update whitelist payload and require returned row',
      () async {
        expect((await repository.saveCourse(draft)).id, courseId);
        expect(requests.single.method, 'POST');
        expect(jsonDecode(requests.single.body), draft.toJson());
        expect(
          requests.single.headers['prefer'],
          contains('return=representation'),
        );
        expect(
          requests.single.headers['accept'],
          'application/vnd.pgrst.object+json',
        );
        await repository.saveCourse(draft, id: courseId);
        expect(requests.last.method, 'PATCH');
        expect(requests.last.url.queryParameters['id'], 'eq.$courseId');
        expect(requests.last.url.queryParameters['deleted_at'], 'is.null');
        expect(jsonDecode(requests.last.body), draft.toJson());
      },
    );
    test('session insert includes course; update never changes it', () async {
      await repository.saveSession(courseId, sessionDraft);
      expect(jsonDecode(requests.single.body), {
        ...sessionDraft.toJson(),
        'course_id': courseId,
      });
      await repository.saveSession(courseId, sessionDraft, id: sessionId);
      expect(jsonDecode(requests.last.body), sessionDraft.toJson());
      expect(requests.last.url.queryParameters['course_id'], 'eq.$courseId');
      expect(requests.last.url.queryParameters['id'], 'eq.$sessionId');
      expect(
        requests.last.headers['accept'],
        'application/vnd.pgrst.object+json',
      );
    });
    test('zero affected update fails with a sanitized message', () async {
      responseStatus = 406;
      responseOverride = {
        'code': 'PGRST116',
        'message': 'secret URL token',
        'details': '0 rows',
        'hint': null,
      };
      await expectLater(
        repository.saveCourse(draft, id: courseId),
        throwsA(
          isA<ContentFailure>().having(
            (e) => e.toString(),
            'sanitized',
            isNot(contains('secret')),
          ),
        ),
      );
      await expectLater(
        repository.saveSession(courseId, sessionDraft, id: sessionId),
        throwsA(isA<ContentFailure>()),
      );
    });
    test('RLS and duplicate errors are sanitized', () async {
      responseStatus = 403;
      responseOverride = {'code': '42501', 'message': 'raw private details'};
      await expectLater(
        repository.listCourses(),
        throwsA(
          isA<ContentFailure>().having(
            (e) => e.message,
            'message',
            isNot(contains('private')),
          ),
        ),
      );
      responseStatus = 409;
      responseOverride = {'code': '23505', 'message': 'raw constraint'};
      await expectLater(
        repository.saveSession(courseId, sessionDraft),
        throwsA(
          isA<ContentFailure>().having(
            (e) => e.message,
            'message',
            contains('session number'),
          ),
        ),
      );
    });
    test(
      'malformed response fails instead of claiming a saved course',
      () async {
        responseOverride = <String, dynamic>{};
        await expectLater(
          repository.saveCourse(draft),
          throwsA(isA<ContentFailure>()),
        );
      },
    );
    for (final isSession in [false, true]) {
      final entity = isSession ? 'session' : 'course';
      Map<String, dynamic> lifecycleRow(bool deleted, {String? status}) => {
        ...(isSession ? sessionRow() : courseRow()),
        'deleted_at': deleted ? '2026-10-18T12:00:00Z' : null,
        'status': status ?? (deleted ? 'archived' : 'draft'),
      };
      Future<Object> change(bool deleted) => isSession
          ? repository.setSessionDeleted(courseId, sessionId, deleted)
          : repository.setCourseDeleted(courseId, deleted);

      for (final deleted in [true, false]) {
        test(
          '$entity ${deleted ? 'delete' : 'restore'} sends only deleted_at and confirms server row',
          () async {
            responseOverride = lifecycleRow(deleted);
            final before = DateTime.now().toUtc();
            final result = await change(deleted);
            final after = DateTime.now().toUtc();
            final request = requests.single;
            expect(request.method, 'PATCH');
            expect(
              request.url.path,
              '/rest/v1/${isSession ? 'course_sessions' : 'courses'}',
            );
            expect(
              request.url.queryParameters['id'],
              'eq.${isSession ? sessionId : courseId}',
            );
            expect(request.url.queryParameters['select'], '*');
            expect(request.url.queryParameters, isNot(contains('deleted_at')));
            if (isSession) {
              expect(request.url.queryParameters['course_id'], 'eq.$courseId');
            } else {
              expect(request.url.queryParameters, isNot(contains('course_id')));
            }
            expect(
              request.headers['accept'],
              'application/vnd.pgrst.object+json',
            );
            expect(
              request.headers['prefer'],
              contains('return=representation'),
            );
            final payload = jsonDecode(request.body) as Map<String, dynamic>;
            expect(payload.keys, ['deleted_at']);
            if (deleted) {
              final timestamp = DateTime.parse(payload['deleted_at'] as String);
              expect(timestamp.isUtc, isTrue);
              expect(timestamp.isBefore(before), isFalse);
              expect(timestamp.isAfter(after), isFalse);
            } else {
              expect(payload, {'deleted_at': null});
            }
            if (result is Course) {
              expect(result.isDeleted, deleted);
              expect(
                result.status,
                deleted ? ContentStatus.archived : ContentStatus.draft,
              );
            } else {
              expect((result as CourseSession).isDeleted, deleted);
              expect(
                result.status,
                deleted ? ContentStatus.archived : ContentStatus.draft,
              );
            }
          },
        );
        test(
          '$entity lifecycle zero affected ${deleted ? 'delete' : 'restore'} fails sanitized',
          () async {
            responseStatus = 406;
            responseOverride = {
              'code': 'PGRST116',
              'message': 'secret token details',
              'details': '0 rows',
            };
            await expectLater(
              change(deleted),
              throwsA(
                isA<ContentFailure>().having(
                  (error) => error.message,
                  'sanitized',
                  isNot(contains('secret')),
                ),
              ),
            );
          },
        );
        test(
          '$entity lifecycle rejects unconfirmed ${deleted ? 'delete' : 'restore'} state',
          () async {
            responseOverride = lifecycleRow(!deleted);
            await expectLater(change(deleted), throwsA(isA<ContentFailure>()));
          },
        );
        test(
          '$entity repeated ${deleted ? 'delete' : 'restore'} safely confirms the same final state',
          () async {
            responseOverride = lifecycleRow(deleted);
            await change(deleted);
            await change(deleted);
            expect(requests, hasLength(2));
            expect(
              requests.every((request) => request.method == 'PATCH'),
              isTrue,
            );
            expect(
              requests.every(
                (request) =>
                    (jsonDecode(request.body) as Map).keys.single ==
                    'deleted_at',
              ),
              isTrue,
            );
            expect(
              requests.every(
                (request) =>
                    !request.url.queryParameters.containsKey('deleted_at'),
              ),
              isTrue,
            );
          },
        );
      }
      test(
        '$entity restore requires server draft and never publishes',
        () async {
          for (final status in ['published', 'archived']) {
            responseOverride = lifecycleRow(false, status: status);
            await expectLater(change(false), throwsA(isA<ContentFailure>()));
            expect(jsonDecode(requests.last.body), {'deleted_at': null});
          }
        },
      );
      test('$entity lifecycle rejects wrong returned identity', () async {
        responseOverride = {
          ...lifecycleRow(true),
          'id': '33333333-3333-4333-8333-333333333333',
        };
        await expectLater(change(true), throwsA(isA<ContentFailure>()));
        if (isSession) {
          responseOverride = {...lifecycleRow(true), 'course_id': sessionId};
          await expectLater(change(true), throwsA(isA<ContentFailure>()));
        }
      });
      test(
        '$entity lifecycle malformed and permission failures are sanitized',
        () async {
          responseOverride = <dynamic>[];
          await expectLater(change(true), throwsA(isA<ContentFailure>()));
          responseStatus = 403;
          responseOverride = {'code': '42501', 'message': 'private token URL'};
          await expectLater(
            change(false),
            throwsA(
              isA<ContentFailure>().having(
                (error) => error.toString(),
                'sanitized',
                isNot(contains('private')),
              ),
            ),
          );
        },
      );
    }
    test('lifecycle invalid identifiers cause no request', () async {
      for (final deleted in [true, false]) {
        await expectLater(
          repository.setCourseDeleted('invalid', deleted),
          throwsA(isA<ContentFailure>()),
        );
        await expectLater(
          repository.setSessionDeleted('invalid', sessionId, deleted),
          throwsA(isA<ContentFailure>()),
        );
        await expectLater(
          repository.setSessionDeleted(courseId, 'invalid', deleted),
          throwsA(isA<ContentFailure>()),
        );
      }
      expect(requests, isEmpty);
    });
    test('invalid drafts, IDs and offsets cause no request', () async {
      await expectLater(
        repository.listCourses(offset: -1),
        throwsA(isA<ContentFailure>()),
      );
      await expectLater(
        repository.listSessions('invalid'),
        throwsA(isA<ContentFailure>()),
      );
      await expectLater(
        repository.saveCourse(draft, id: 'invalid'),
        throwsA(isA<ContentFailure>()),
      );
      await expectLater(
        repository.saveSession(
          courseId,
          const SessionDraft(sessionNumber: 0, title: 'T', pricePiasters: 0),
        ),
        throwsA(isA<ContentFailure>()),
      );
      expect(requests, isEmpty);
    });
  });
}
