import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/auth/auth_controller.dart';
import 'package:summit_academy/auth/auth_repository.dart';
import 'package:summit_academy/content/admin_content_screen.dart';
import 'package:summit_academy/content/content_repository.dart';

import 'auth_fakes.dart';

Course course(String title, {String id = 'course-1', DateTime? deletedAt}) =>
    Course(
      id: id,
      title: title,
      instructor: 'Teacher',
      category: 'Engineering',
      level: 'Beginner',
      pricePiasters: 10001,
      deletedAt: deletedAt,
    );
CourseSession session(String title) => CourseSession(
  id: 'session-1',
  courseId: 'course-1',
  sessionNumber: 1,
  title: title,
  pricePiasters: 123,
);

class FakeContentRepository implements ContentRepository {
  bool lifecycleFilter = false;
  Object? lifecycleError;
  Completer<Course>? lifecyclePending;
  final courseVisibility = <(String, bool)>[];
  final sessionVisibility = <(String, String, bool)>[];
  @override
  Future<Course> setCourseDeleted(String id, bool deleted) async {
    courseVisibility.add((id, deleted));
    if (lifecycleError != null) throw lifecycleError!;
    if (lifecyclePending != null) return lifecyclePending!.future;
    final old = courses.singleWhere((item) => item.id == id);
    final saved = Course.fromJson({
      ...old.toDraft().toJson(),
      'id': id,
      'deleted_at': deleted
          ? DateTime.utc(2026, 10, 18).toIso8601String()
          : null,
      'status': deleted ? 'archived' : 'draft',
    });
    courses = [
      for (final item in courses)
        if (item.id == id) saved else item,
    ];
    return saved;
  }

  @override
  Future<CourseSession> setSessionDeleted(
    String courseId,
    String id,
    bool deleted,
  ) async {
    sessionVisibility.add((courseId, id, deleted));
    if (lifecycleError != null) throw lifecycleError!;
    final old = sessions.singleWhere((item) => item.id == id);
    final saved = CourseSession.fromJson({
      ...old.toDraft().toJson(),
      'id': id,
      'course_id': courseId,
      'deleted_at': deleted
          ? DateTime.utc(2026, 10, 18).toIso8601String()
          : null,
      'status': deleted ? 'archived' : 'draft',
    });
    sessions = [
      for (final item in sessions)
        if (item.id == id) saved else item,
    ];
    return saved;
  }

  List<Course> courses = [course('Existing course')];
  List<CourseSession> sessions = [session('Existing session')];
  final courseRequests = <(int, bool)>[];
  final sessionRequests = <(String, int, bool)>[];
  final courseSaves = <(CourseDraft, String?)>[];
  final sessionSaves = <(String, SessionDraft, String?)>[];
  Completer<List<Course>>? coursePending;
  Completer<List<CourseSession>>? sessionPending;
  Completer<Course>? savePending;
  Object? loadError, saveError;
  @override
  Future<List<Course>> listCourses({
    int offset = 0,
    bool includeDeleted = false,
  }) async {
    courseRequests.add((offset, includeDeleted));
    if (loadError != null) throw loadError!;
    if (coursePending != null) return coursePending!.future;
    return courses
        .where((item) => !lifecycleFilter || includeDeleted || !item.isDeleted)
        .skip(offset)
        .take(contentPageSize)
        .toList();
  }

  @override
  Future<List<CourseSession>> listSessions(
    String courseId, {
    int offset = 0,
    bool includeDeleted = false,
  }) async {
    sessionRequests.add((courseId, offset, includeDeleted));
    if (loadError != null) throw loadError!;
    if (sessionPending != null) return sessionPending!.future;
    return sessions
        .where((item) => !lifecycleFilter || includeDeleted || !item.isDeleted)
        .skip(offset)
        .take(contentPageSize)
        .toList();
  }

  @override
  Future<Course> saveCourse(CourseDraft draft, {String? id}) async {
    courseSaves.add((draft, id));
    if (saveError != null) throw saveError!;
    if (savePending != null) return savePending!.future;
    final saved = Course(
      id: id ?? 'new-course',
      title: draft.title,
      description: draft.description,
      instructor: draft.instructor,
      category: draft.category,
      level: draft.level,
      pricePiasters: draft.pricePiasters,
      position: draft.position,
      status: draft.status,
    );
    courses = [...courses.where((item) => item.id != saved.id), saved];
    return saved;
  }

  @override
  Future<CourseSession> saveSession(
    String courseId,
    SessionDraft draft, {
    String? id,
  }) async {
    sessionSaves.add((courseId, draft, id));
    if (saveError != null) throw saveError!;
    final saved = CourseSession(
      id: id ?? 'new-session',
      courseId: courseId,
      sessionNumber: draft.sessionNumber,
      title: draft.title,
      description: draft.description,
      pricePiasters: draft.pricePiasters,
      position: draft.position,
      status: draft.status,
      isFreePreview: draft.isFreePreview,
    );
    sessions = [...sessions.where((item) => item.id != saved.id), saved];
    return saved;
  }
}

void main() {
  late FakeAuthRepository authRepository;
  late AuthController auth;
  late FakeContentRepository repository;
  setUp(() async {
    authRepository = FakeAuthRepository()
      ..hasSession = true
      ..accessContext = const AccessContext(
        'admin',
        '11111111-1111-4111-8111-111111111111',
      );
    auth = AuthController(authRepository);
    await auth.start();
    repository = FakeContentRepository();
  });
  tearDown(() async {
    auth.dispose();
    await authRepository.dispose();
  });

  Future<void> show(WidgetTester tester, {bool settle = true}) async {
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: AdminContentScreen(repository: repository, authController: auth),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  Finder field(String label) => find.widgetWithText(TextFormField, label);
  Future<void> enter(WidgetTester tester, String label, String value) async {
    await tester.ensureVisible(field(label));
    await tester.enterText(field(label), value);
  }

  Future<void> tap(WidgetTester tester, String label) async {
    await tester.ensureVisible(find.text(label).last);
    await tester.tap(find.text(label).last);
    await tester.pumpAndSettle();
  }

  Future<void> fillCourse(WidgetTester tester) async {
    await enter(tester, 'Title', 'New engineering course');
    await enter(tester, 'Instructor', 'Instructor');
    await enter(tester, 'Category', 'Civil');
    await enter(tester, 'Level', 'Advanced');
    await enter(tester, 'Price (EGP)', '123.45');
  }

  testWidgets('course deletion can be cancelled and restore returns draft', (
    tester,
  ) async {
    repository.lifecycleFilter = true;
    await show(tester);
    await tap(tester, 'Delete course');
    expect(
      find.textContaining('Its sessions will also be hidden.'),
      findsOneWidget,
    );
    await tap(tester, 'Cancel');
    expect(repository.courseVisibility, isEmpty);
    await tap(tester, 'Delete course');
    await tap(tester, 'Confirm delete');
    expect(repository.courseVisibility, [('course-1', true)]);
    expect(find.text('Existing course'), findsNothing);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tap(tester, 'Restore course');
    expect(find.textContaining('return to draft'), findsOneWidget);
    await tap(tester, 'Confirm restore');
    expect(repository.courseVisibility.last, ('course-1', false));
    expect(repository.courses.single.status, ContentStatus.draft);
    expect(find.text('Edit course'), findsOneWidget);
  });

  testWidgets('session delete and restore stay scoped to selected course', (
    tester,
  ) async {
    repository.lifecycleFilter = true;
    await show(tester);
    await tap(tester, 'Sessions');
    await tap(tester, 'Delete session');
    await tap(tester, 'Confirm delete');
    expect(repository.sessionVisibility, [('course-1', 'session-1', true)]);
    expect(find.text('1. Existing session'), findsNothing);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tap(tester, 'Restore session');
    await tap(tester, 'Confirm restore');
    expect(repository.sessionVisibility.last, ('course-1', 'session-1', false));
    expect(repository.sessions.single.status, ContentStatus.draft);
  });

  testWidgets(
    'delete failure is sanitized and does not remove content locally',
    (tester) async {
      repository.lifecycleError = StateError('private backend data');
      await show(tester);
      await tap(tester, 'Delete course');
      await tap(tester, 'Confirm delete');
      expect(
        find.textContaining('Unable to change content visibility'),
        findsOneWidget,
      );
      expect(find.textContaining('private backend data'), findsNothing);
      expect(find.text('Existing course'), findsOneWidget);
      expect(repository.courses.single.isDeleted, isFalse);
    },
  );

  testWidgets(
    'revoked access during confirmation prevents lifecycle mutation',
    (tester) async {
      await show(tester);
      await tap(tester, 'Delete course');
      auth.lock('device_revoked');
      await tester.pumpAndSettle();
      expect(find.text('Access changed'), findsOneWidget);
      final confirm = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Confirm delete'),
      );
      expect(confirm.onPressed, isNull);
      await tap(tester, 'Cancel');
      expect(repository.courseVisibility, isEmpty);
      expect(find.text('Administrator access is required.'), findsOneWidget);
    },
  );

  testWidgets('late deletion response cannot reopen revoked content', (
    tester,
  ) async {
    await show(tester);
    final pending = Completer<Course>();
    repository.lifecyclePending = pending;
    await tap(tester, 'Delete course');
    await tester.tap(find.text('Confirm delete'));
    await tester.pump();
    auth.lock('session_replaced');
    pending.complete(course('Late deleted course'));
    await tester.pumpAndSettle();
    expect(find.text('Administrator access is required.'), findsOneWidget);
    expect(find.text('Late deleted course'), findsNothing);
    expect(repository.courseRequests, hasLength(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('session lifecycle actions fit a narrow phone', (tester) async {
    await show(tester);
    await tap(tester, 'Sessions');
    await tester.binding.setSurfaceSize(const Size(320, 640));
    await tester.pumpAndSettle();
    expect(find.text('Delete session'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('student cannot load lists or access editors', (tester) async {
    authRepository.accessContext = FakeAuthRepository.context;
    await tester.runAsync(auth.checkAccess);
    await show(tester);
    expect(find.text('Administrator access is required.'), findsOneWidget);
    expect(find.text('New course'), findsNothing);
    expect(repository.courseRequests, isEmpty);
  });
  testWidgets('admin creates a course with exact price and explicit status', (
    tester,
  ) async {
    await show(tester);
    await tap(tester, 'New course');
    await fillCourse(tester);
    await tester.ensureVisible(
      find.byType(DropdownButtonFormField<ContentStatus>),
    );
    await tester.tap(find.byType(DropdownButtonFormField<ContentStatus>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('published').last);
    await tester.pumpAndSettle();
    await tap(tester, 'Save');
    expect(repository.courseSaves, hasLength(1));
    expect(repository.courseSaves.single.$1.pricePiasters, 12345);
    expect(repository.courseSaves.single.$1.status, ContentStatus.published);
    expect(repository.courseSaves.single.$2, isNull);
    expect(find.text('New engineering course'), findsOneWidget);
  });
  testWidgets('invalid money and required fields never save', (tester) async {
    await show(tester);
    await tap(tester, 'New course');
    await enter(tester, 'Price (EGP)', '0.001');
    await tap(tester, 'Save');
    expect(find.text('Title is required.'), findsOneWidget);
    expect(
      find.text('Enter a valid EGP price with at most 2 decimal places.'),
      findsOneWidget,
    );
    expect(repository.courseSaves, isEmpty);
    await fillCourse(tester);
    await enter(tester, 'Price (EGP)', '21474836.48');
    await tap(tester, 'Save');
    expect(repository.courseSaves, isEmpty);
  });
  testWidgets('edit preserves identifier and can archive', (tester) async {
    await show(tester);
    await tap(tester, 'Edit course');
    expect(
      tester.widget<TextFormField>(field('Title')).controller!.text,
      'Existing course',
    );
    await enter(tester, 'Title', 'Changed course');
    await tester.ensureVisible(
      find.byType(DropdownButtonFormField<ContentStatus>),
    );
    await tester.tap(find.byType(DropdownButtonFormField<ContentStatus>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('archived').last);
    await tester.pumpAndSettle();
    await tap(tester, 'Save');
    expect(repository.courseSaves.single.$2, 'course-1');
    expect(repository.courseSaves.single.$1.status, ContentStatus.archived);
  });
  testWidgets('sessions create and edit keep their selected course', (
    tester,
  ) async {
    await show(tester);
    await tap(tester, 'Sessions');
    expect(find.text('1. Existing session'), findsOneWidget);
    await tap(tester, 'New session');
    await enter(tester, 'Title', 'New session title');
    await enter(tester, 'Session number', '0');
    await tap(tester, 'Save');
    expect(repository.sessionSaves, isEmpty);
    await enter(tester, 'Session number', '2');
    await enter(tester, 'Price (EGP)', '0.01');
    await tap(tester, 'Free preview');
    await tap(tester, 'Save');
    expect(repository.sessionSaves.single.$1, 'course-1');
    expect(repository.sessionSaves.single.$2.sessionNumber, 2);
    expect(repository.sessionSaves.single.$2.pricePiasters, 1);
    expect(repository.sessionSaves.single.$2.isFreePreview, isTrue);
    await tester.tap(find.text('Edit session').first);
    await tester.pumpAndSettle();
    await enter(tester, 'Title', 'Updated session');
    await tap(tester, 'Save');
    expect(repository.sessionSaves.last.$3, 'session-1');
  });
  testWidgets('course pagination and include-deleted reset offset', (
    tester,
  ) async {
    repository.courses = List.generate(
      21,
      (index) => course('Course $index', id: 'c$index'),
    );
    await show(tester);
    await tap(tester, 'Next');
    expect(repository.courseRequests.last, (20, false));
    expect(find.text('Course 20'), findsOneWidget);
    await tap(tester, 'Previous');
    expect(repository.courseRequests.last, (0, false));
    await tap(tester, 'Next');
    await tap(tester, 'Include deleted');
    expect(repository.courseRequests.last, (0, true));
    expect(find.text('Page 1'), findsOneWidget);
  });
  testWidgets(
    'session pagination uses course and empty next page can go back',
    (tester) async {
      repository.sessions = List.generate(
        20,
        (index) => CourseSession(
          id: 's$index',
          courseId: 'course-1',
          sessionNumber: index + 1,
          title: 'Session $index',
          pricePiasters: 0,
        ),
      );
      await show(tester);
      await tap(tester, 'Sessions');
      await tap(tester, 'Next');
      expect(repository.sessionRequests.last, ('course-1', 20, false));
      expect(find.text('No content on this page.'), findsOneWidget);
      await tap(tester, 'Previous');
      await tap(tester, 'Include deleted');
      expect(repository.sessionRequests.last, ('course-1', 0, true));
    },
  );
  testWidgets('deleted courses are visibly read-only', (tester) async {
    repository.courses = [
      course('Deleted course', deletedAt: DateTime.utc(2026)),
    ];
    await show(tester);
    expect(find.textContaining('Deleted'), findsWidgets);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Edit course'))
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Sessions'))
          .onPressed,
      isNull,
    );
  });
  testWidgets('save failure retains form without displaying raw exception', (
    tester,
  ) async {
    repository.saveError = StateError('secret token raw server response');
    await show(tester);
    await tap(tester, 'Edit course');
    await enter(tester, 'Title', 'Unsaved title');
    await tap(tester, 'Save');
    expect(
      tester.widget<TextFormField>(field('Title')).controller!.text,
      'Unsaved title',
    );
    expect(find.textContaining('Unable to save content.'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
    repository.saveError = null;
    await tap(tester, 'Save');
    expect(find.text('Unsaved title'), findsOneWidget);
  });
  testWidgets('load failure offers working refresh with sanitized error', (
    tester,
  ) async {
    repository.loadError = StateError('private response');
    await show(tester);
    expect(find.textContaining('Unable to load content.'), findsOneWidget);
    expect(find.textContaining('private'), findsNothing);
    repository.loadError = null;
    await tap(tester, 'Refresh');
    expect(find.text('Existing course'), findsOneWidget);
  });
  testWidgets('suspend hides editor and reopening discards unsaved text', (
    tester,
  ) async {
    await show(tester);
    await tap(tester, 'Edit course');
    await enter(tester, 'Title', 'Sensitive unsaved title');
    auth.suspend();
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Administrator access is required.'), findsOneWidget);
    await tester.runAsync(auth.checkAccess);
    await tester.pumpAndSettle();
    expect(find.text('Existing course'), findsOneWidget);
    expect(find.text('Sensitive unsaved title'), findsNothing);
    await tap(tester, 'Edit course');
    expect(
      tester.widget<TextFormField>(field('Title')).controller!.text,
      'Existing course',
    );
  });
  testWidgets('rapid close and reopen before a frame still resets editor', (
    tester,
  ) async {
    await show(tester);
    await tap(tester, 'Edit course');
    await enter(tester, 'Title', 'Discard me');
    auth.suspend();
    await tester.runAsync(auth.checkAccess);
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Existing course'), findsOneWidget);
    expect(find.text('Discard me'), findsNothing);
    expect(repository.courseRequests, hasLength(2));
  });
  testWidgets(
    'pending load after revocation cannot restore protected content',
    (tester) async {
      final pending = Completer<List<Course>>();
      repository.coursePending = pending;
      await show(tester, settle: false);
      auth.lock('device_revoked');
      await tester.pump();
      pending.complete([course('Late private content')]);
      await tester.pumpAndSettle();
      expect(find.text('Late private content'), findsNothing);
      expect(find.text('Administrator access is required.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
  testWidgets('pending session load after logout cannot restore content', (
    tester,
  ) async {
    await show(tester);
    final pending = Completer<List<CourseSession>>();
    repository.sessionPending = pending;
    await tester.tap(find.text('Sessions'));
    await tester.pump();
    await tester.runAsync(auth.logout);
    pending.complete([session('Late session')]);
    await tester.pumpAndSettle();
    expect(find.textContaining('Late session'), findsNothing);
    expect(find.text('Administrator access is required.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('pending save after role loss cannot reopen list or editor', (
    tester,
  ) async {
    await show(tester);
    await tap(tester, 'Edit course');
    final pending = Completer<Course>();
    repository.savePending = pending;
    await tester.ensureVisible(find.text('Save'));
    await tester.tap(find.text('Save'));
    await tester.pump();
    authRepository.accessContext = FakeAuthRepository.context;
    await tester.runAsync(auth.checkAccess);
    pending.complete(course('Late saved course'));
    await tester.pumpAndSettle();
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Late saved course'), findsNothing);
    expect(repository.courseRequests, hasLength(1));
    expect(tester.takeException(), isNull);
  });
}
