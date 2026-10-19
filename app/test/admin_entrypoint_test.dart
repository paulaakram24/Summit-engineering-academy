import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/auth/auth_controller.dart';
import 'package:summit_academy/auth/auth_panel.dart';
import 'package:summit_academy/auth/auth_repository.dart';
import 'package:summit_academy/content/content_repository.dart';

import 'auth_fakes.dart';

class _Content extends ContentRepository {
  @override
  Future<Course> setCourseDeleted(String id, bool deleted) async =>
      throw UnimplementedError();
  @override
  Future<CourseSession> setSessionDeleted(
    String courseId,
    String id,
    bool deleted,
  ) async => throw UnimplementedError();
  int loads = 0;
  @override
  Future<List<Course>> listCourses({
    int offset = 0,
    bool includeDeleted = false,
  }) async {
    loads++;
    return [];
  }

  @override
  Future<List<CourseSession>> listSessions(
    String courseId, {
    int offset = 0,
    bool includeDeleted = false,
  }) async => [];
  @override
  Future<Course> saveCourse(CourseDraft draft, {String? id}) async =>
      throw UnimplementedError();
  @override
  Future<CourseSession> saveSession(
    String courseId,
    SessionDraft draft, {
    String? id,
  }) async => throw UnimplementedError();
}

void main() {
  for (final role in ['student', 'admin']) {
    testWidgets('$role sees only the authorized course entry point', (
      tester,
    ) async {
      final account = FakeAuthRepository()..hasSession = true;
      account.accessContext = AccessContext(
        role,
        '11111111-1111-4111-8111-111111111111',
      );
      final auth = AuthController(account);
      final content = _Content();
      await auth.start();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: AuthPanel(controller: auth, contentRepository: content),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      if (role == 'student') {
        expect(find.text('Manage courses'), findsNothing);
        expect(content.loads, 0);
      } else {
        final button = find.text('Manage courses');
        await tester.ensureVisible(button);
        await tester.tap(button);
        await tester.pumpAndSettle();
        expect(find.text('Course administration'), findsOneWidget);
        expect(content.loads, 1);
        auth.lock('session_replaced');
        await tester.pumpAndSettle();
        expect(find.text('Administrator access is required.'), findsOneWidget);
        expect(find.text('New course'), findsNothing);
      }
      await tester.pumpWidget(const SizedBox());
      auth.dispose();
      await account.dispose();
    });
  }
}
