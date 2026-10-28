import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/auth/auth_controller.dart';
import 'package:summit_academy/auth/auth_repository.dart';
import 'package:summit_academy/commerce/course_payment_instructor_panel.dart';
import 'package:summit_academy/commerce/instructor_payment_repository.dart';
import 'package:summit_academy/content/content_models.dart';

import 'auth_fakes.dart';

String identity(int n) =>
    'f3c0e400-0000-4000-8000-${n.toString().padLeft(12, '0')}';
Course fixtureCourse({int n = 201, bool deleted = false}) => Course(
  id: identity(n),
  title: 'Fixture course',
  instructor: 'Display only',
  category: 'Engineering',
  level: '1',
  pricePiasters: 100,
  deletedAt: deleted ? DateTime.utc(2026) : null,
);
PaymentInstructorDirectoryEntry entry(int n, {String? name}) =>
    PaymentInstructorDirectoryEntry(
      instructorId: identity(n),
      displayName: name ?? 'Instructor $n',
    );

class AssignmentRepository implements InstructorPaymentRepository {
  @override
  String? currentActorId = identity(1);
  CoursePaymentInstructor? binding;
  List<PaymentInstructorDirectoryEntry> rows = [entry(2), entry(3)];
  final gets = <(String, String)>[];
  final lists = <(String, PaymentInstructorCursor?, int)>[];
  final writes = <SetCoursePaymentInstructorRequest>[];
  Completer<CoursePaymentInstructor?>? pendingGet;
  Completer<PaymentInstructorPage>? pendingList;
  Completer<CoursePaymentInstructor>? pendingSet;
  Object? getError, listError, setError;
  PaymentInstructorPage? pageOverride;
  VoidCallback? afterSet;
  int profileCalls = 0;

  @override
  Future<CoursePaymentInstructor?> getCourseInstructor({
    required String actorId,
    required String courseId,
  }) async {
    gets.add((actorId, courseId));
    if (getError != null) throw getError!;
    if (pendingGet != null) return pendingGet!.future;
    return binding;
  }

  @override
  Future<PaymentInstructorPage> listInstructors({
    required String actorId,
    PaymentInstructorCursor? after,
    int limit = 20,
  }) async {
    lists.add((actorId, after, limit));
    if (listError != null) throw listError!;
    if (pendingList != null) return pendingList!.future;
    if (pageOverride != null) return pageOverride!;
    final remaining = rows
        .where((row) => after == null || row.cursor.compareTo(after) > 0)
        .toList();
    final items = remaining.take(limit).toList();
    return PaymentInstructorPage(
      items: items,
      hasMore: remaining.length > limit,
      nextCursor: remaining.length > limit ? items.last.cursor : null,
      after: after,
      limit: limit,
    );
  }

  @override
  Future<CoursePaymentInstructor> setCourseInstructor(
    SetCoursePaymentInstructorRequest request,
  ) async {
    writes.add(request);
    if (setError != null) throw setError!;
    if (pendingSet != null) return pendingSet!.future;
    binding = CoursePaymentInstructor(
      courseId: request.courseId,
      instructorId: request.instructorId,
      revision: request.expectedRevision + 1,
    );
    afterSet?.call();
    return binding!;
  }

  @override
  Future<InstructorPaymentProfile?> getMyProfile({
    required String actorId,
  }) async {
    profileCalls++;
    throw StateError('Profile access is outside assignment scope');
  }

  @override
  Future<InstructorPaymentProfile> saveMyProfile(
    SaveInstructorPaymentProfileRequest request,
  ) async {
    profileCalls++;
    throw StateError('Profile access is outside assignment scope');
  }
}

void main() {
  late FakeAuthRepository accounts;
  late AuthController auth;
  late AssignmentRepository repository;
  var closed = 0;
  setUp(() async {
    accounts = FakeAuthRepository()
      ..hasSession = true
      ..accessContext = AccessContext('admin', identity(101));
    auth = AuthController(accounts);
    await auth.start();
    repository = AssignmentRepository();
    closed = 0;
  });
  tearDown(() async {
    auth.dispose();
    await accounts.dispose();
  });
  Future<void> show(
    WidgetTester tester, {
    Course? course,
    AssignmentRepository? source,
    Size size = const Size(800, 1400),
    double scale = 1,
    bool settle = true,
  }) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(scale),
          ),
          child: Scaffold(
            body: CoursePaymentInstructorPanel(
              course: course ?? fixtureCourse(),
              auth: auth,
              repository: source ?? repository,
              onClose: () => closed++,
            ),
          ),
        ),
      ),
    );
    if (settle) await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, String label) async {
    final finder = find.text(label);
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        250,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await Scrollable.ensureVisible(tester.element(finder.last), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(finder.last);
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester, int n) async {
    final finder = find.byKey(ValueKey('instructor-${identity(n)}'));
    if (finder.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        finder,
        250,
        scrollable: find.byType(Scrollable).first,
      );
    }
    await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Future<void> confirm(WidgetTester tester) async {
    await select(tester, 2);
    await tap(tester, 'Assign instructor');
    await tap(tester, 'Confirm assignment');
  }

  testWidgets(
    'fresh null binding and safe directory load without profile calls',
    (tester) async {
      await show(tester);
      expect(find.text('No instructor assigned.'), findsOneWidget);
      expect(find.text('Instructor 2 · 00000002'), findsOneWidget);
      expect(repository.gets, [(identity(1), identity(201))]);
      expect(repository.lists.single.$3, 20);
      expect(repository.profileCalls, 0);
      expect(repository.writes, isEmpty);
    },
  );
  testWidgets('student cannot load or select', (tester) async {
    auth.access = AccessContext('student', identity(101));
    await show(tester);
    expect(repository.gets, isEmpty);
    expect(repository.lists, isEmpty);
    expect(find.textContaining('Reopen setup'), findsOneWidget);
  });
  testWidgets('deleted course cannot load', (tester) async {
    await show(tester, course: fixtureCourse(deleted: true));
    expect(repository.gets, isEmpty);
  });
  testWidgets('invalid actor cannot load', (tester) async {
    repository.currentActorId = 'invalid';
    await show(tester);
    expect(repository.gets, isEmpty);
  });
  testWidgets('binding outside loaded page is UUID not false missing claim', (
    tester,
  ) async {
    repository.binding = CoursePaymentInstructor(
      courseId: identity(201),
      instructorId: identity(90),
      revision: 4,
    );
    await show(tester);
    expect(
      find.textContaining('Current instructor UUID: ${identity(90)}'),
      findsOneWidget,
    );
    expect(
      find.textContaining('eligibility has not been confirmed'),
      findsOneWidget,
    );
    expect(repository.writes, isEmpty);
  });
  testWidgets(
    'cancel confirmation sends no write and explains setup boundary',
    (tester) async {
      await show(tester);
      await select(tester, 2);
      await tap(tester, 'Assign instructor');
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('same-course bundles inherit'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('Checkout is off'),
        ),
        findsOneWidget,
      );
      await tap(tester, 'Cancel');
      expect(repository.writes, isEmpty);
    },
  );
  testWidgets('initial confirmed assignment uses CAS zero and refetches both', (
    tester,
  ) async {
    await show(tester);
    await confirm(tester);
    expect(repository.writes.single.expectedRevision, 0);
    expect(repository.writes.single.actorId, identity(1));
    expect(repository.writes.single.instructorId, identity(2));
    expect(repository.gets.length, 2);
    expect(repository.lists.length, 2);
    expect(find.text('Assignment saved. Fresh setup loaded.'), findsOneWidget);
    expect(
      find.textContaining('Current instructor: Instructor 2'),
      findsOneWidget,
    );
  });
  testWidgets(
    'reassignment uses fresh binding revision and never selects current',
    (tester) async {
      repository.binding = CoursePaymentInstructor(
        courseId: identity(201),
        instructorId: identity(3),
        revision: 7,
      );
      await show(tester);
      await select(tester, 3);
      expect(
        tester
            .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Assign instructor'),
            )
            .onPressed,
        isNull,
      );
      await confirm(tester);
      expect(repository.writes.single.expectedRevision, 7);
    },
  );
  testWidgets('timeout clears state allows refresh only no automatic retry', (
    tester,
  ) async {
    repository.setError = const InstructorPaymentFailure(
      InstructorPaymentFailureKind.timedOut,
    );
    await show(tester);
    await confirm(tester);
    expect(repository.writes.length, 1);
    expect(find.byKey(ValueKey('instructor-${identity(2)}')), findsNothing);
    expect(find.textContaining('timed out'), findsOneWidget);
    await tap(tester, 'Refresh');
    expect(repository.writes.length, 1);
    expect(repository.gets.length, 2);
    expect(find.textContaining('Selected:'), findsNothing);
  });
  testWidgets('unavailable target discards binding and choices', (
    tester,
  ) async {
    repository.setError = const InstructorPaymentFailure(
      InstructorPaymentFailureKind.targetUnavailable,
    );
    await show(tester);
    await confirm(tester);
    expect(find.textContaining('Current instructor:'), findsNothing);
    expect(find.byKey(ValueKey('instructor-${identity(2)}')), findsNothing);
    expect(find.textContaining('unavailable'), findsOneWidget);
  });
  testWidgets('conflict requires refresh and never retries', (tester) async {
    repository.setError = const InstructorPaymentFailure(
      InstructorPaymentFailureKind.stateConflict,
    );
    await show(tester);
    await confirm(tester);
    await tester.pump(const Duration(seconds: 10));
    expect(repository.writes.length, 1);
    expect(find.textContaining('changed elsewhere'), findsOneWidget);
  });
  testWidgets('success with failed refetch cannot write again', (tester) async {
    repository.afterSet = () =>
        repository.listError = const InstructorPaymentFailure(
          InstructorPaymentFailureKind.requestFailed,
        );
    await show(tester);
    await confirm(tester);
    expect(repository.gets.length, 2);
    expect(repository.lists.length, 2);
    expect(find.byKey(ValueKey('instructor-${identity(2)}')), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Assign instructor'),
          )
          .onPressed,
      isNull,
    );
  });
  testWidgets(
    'explicit paging uses limit twenty and correct advancing cursor',
    (tester) async {
      repository.rows = List.generate(25, (i) => entry(i + 2));
      await show(tester);
      expect(repository.lists.length, 1);
      await tap(tester, 'Load more instructors');
      expect(repository.lists.last.$2?.instructorId, identity(21));
      expect(repository.lists.last.$3, 20);
      expect(find.text('Load more instructors'), findsNothing);
      await select(tester, 26);
      expect(find.text('Selected: Instructor 26 · 00000026'), findsOneWidget);
    },
  );
  testWidgets('duplicate nonadvancing page discards accumulated state', (
    tester,
  ) async {
    repository.rows = List.generate(25, (i) => entry(i + 2));
    await show(tester);
    repository.pageOverride = PaymentInstructorPage(
      items: [entry(2)],
      hasMore: false,
      nextCursor: null,
    );
    await tap(tester, 'Load more instructors');
    expect(find.byKey(ValueKey('instructor-${identity(2)}')), findsNothing);
    expect(find.textContaining('could not be verified'), findsOneWidget);
    expect(repository.writes, isEmpty);
  });
  testWidgets('access denial while paging removes all old state', (
    tester,
  ) async {
    repository.rows = List.generate(25, (i) => entry(i + 2));
    await show(tester);
    repository.listError = const InstructorPaymentFailure(
      InstructorPaymentFailureKind.accessRequired,
    );
    await tap(tester, 'Load more instructors');
    expect(find.textContaining('Reopen setup'), findsOneWidget);
    expect(find.byKey(ValueKey('instructor-${identity(2)}')), findsNothing);
  });
  testWidgets(
    'duplicate names and colliding UUID suffixes stay distinguishable',
    (tester) async {
      final a = PaymentInstructorDirectoryEntry(
        instructorId: '11111111-1111-4111-8111-111100000002',
        displayName: 'Same',
      );
      final b = PaymentInstructorDirectoryEntry(
        instructorId: '22222222-2222-4222-8222-222200000002',
        displayName: 'Same',
      );
      repository.rows = [a, b];
      await show(tester);
      expect(find.text('Same · 111100000002'), findsOneWidget);
      expect(find.text('Same · 222200000002'), findsOneWidget);
    },
  );
  testWidgets('close dirty selection needs explicit discard', (tester) async {
    await show(tester);
    await select(tester, 2);
    await tap(tester, 'Close');
    expect(closed, 0);
    await tap(tester, 'Cancel');
    expect(closed, 0);
    await tap(tester, 'Close');
    await tap(tester, 'Discard selection');
    expect(closed, 1);
    expect(repository.writes, isEmpty);
  });
  testWidgets('system back uses dirty confirmation', (tester) async {
    await show(tester);
    await select(tester, 2);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Discard selection?'), findsOneWidget);
    expect(closed, 0);
    await tap(tester, 'Discard selection');
    expect(closed, 1);
  });
  testWidgets('role lock dismisses owned confirmation before stale write', (
    tester,
  ) async {
    await show(tester);
    await select(tester, 2);
    await tap(tester, 'Assign instructor');
    auth.lock('device_revoked');
    await tester.pumpAndSettle();
    expect(find.text('Confirm assignment'), findsNothing);
    expect(find.textContaining('Selected:'), findsNothing);
    expect(repository.writes, isEmpty);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'device access object replacement blocks confirmation without notification',
    (tester) async {
      await show(tester);
      await select(tester, 2);
      await tap(tester, 'Assign instructor');
      auth.access = AccessContext('admin', identity(102));
      await tap(tester, 'Confirm assignment');
      expect(repository.writes, isEmpty);
    },
  );
  testWidgets('actor change during confirmation prevents write', (
    tester,
  ) async {
    await show(tester);
    await select(tester, 2);
    await tap(tester, 'Assign instructor');
    repository.currentActorId = identity(9);
    await tap(tester, 'Confirm assignment');
    expect(repository.writes, isEmpty);
  });
  testWidgets(
    'background clears dialog selection and does not resume stale state',
    (tester) async {
      await show(tester);
      await select(tester, 2);
      await tap(tester, 'Assign instructor');
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('Confirm assignment'), findsNothing);
      expect(find.textContaining('Reopen setup'), findsOneWidget);
      expect(repository.writes, isEmpty);
    },
  );
  testWidgets('late first read after auth lock never loads directory', (
    tester,
  ) async {
    final pending = Completer<CoursePaymentInstructor?>();
    repository.pendingGet = pending;
    await show(tester, settle: false);
    auth.lock('device_revoked');
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(repository.lists, isEmpty);
    expect(find.text('No instructor assigned.'), findsNothing);
  });
  testWidgets(
    'repository replacement discards late old binding and directory',
    (tester) async {
      final pending = Completer<CoursePaymentInstructor?>();
      repository.pendingGet = pending;
      final course = fixtureCourse();
      await show(tester, course: course, settle: false);
      final replacement = AssignmentRepository()..rows = [entry(8)];
      await show(tester, course: course, source: replacement);
      pending.complete(
        CoursePaymentInstructor(
          courseId: identity(201),
          instructorId: identity(90),
          revision: 9,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Instructor 8 · 00000008'), findsOneWidget);
      expect(find.textContaining(identity(90)), findsNothing);
      expect(repository.lists, isEmpty);
    },
  );
  testWidgets('busy pending mutation cannot produce second save', (
    tester,
  ) async {
    final pending = Completer<CoursePaymentInstructor>();
    repository.pendingSet = pending;
    await show(tester);
    await select(tester, 2);
    await tap(tester, 'Assign instructor');
    await tester.tap(find.text('Confirm assignment'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(repository.writes.length, 1);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Assign instructor'),
          )
          .onPressed,
      isNull,
    );
    pending.complete(
      CoursePaymentInstructor(
        courseId: identity(201),
        instructorId: identity(2),
        revision: 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.writes.length, 1);
  });
  testWidgets('wrong parent binding is rejected before directory or mutation', (
    tester,
  ) async {
    repository.binding = CoursePaymentInstructor(
      courseId: identity(202),
      instructorId: identity(2),
      revision: 1,
    );
    await show(tester);
    expect(repository.lists, isEmpty);
    expect(find.textContaining('could not be verified'), findsOneWidget);
  });
  testWidgets('late paging after background cannot restore choices', (
    tester,
  ) async {
    repository.rows = List.generate(25, (i) => entry(i + 2));
    await show(tester);
    final pending = Completer<PaymentInstructorPage>();
    repository.pendingList = pending;
    await tester.ensureVisible(find.text('Load more instructors'));
    await tester.tap(find.text('Load more instructors'));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    pending.complete(
      PaymentInstructorPage(
        items: [entry(26)],
        hasMore: false,
        nextCursor: null,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('instructor-${identity(26)}')), findsNothing);
    expect(find.textContaining('Reopen setup'), findsOneWidget);
  });
  testWidgets('late save after actor change never refetches another account', (
    tester,
  ) async {
    final pending = Completer<CoursePaymentInstructor>();
    repository.pendingSet = pending;
    await show(tester);
    await select(tester, 2);
    await tap(tester, 'Assign instructor');
    await tester.tap(find.text('Confirm assignment'));
    await tester.pump(const Duration(milliseconds: 400));
    repository.currentActorId = identity(9);
    pending.complete(
      CoursePaymentInstructor(
        courseId: identity(201),
        instructorId: identity(2),
        revision: 1,
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.gets.length, 1);
    expect(repository.lists.length, 1);
    expect(find.textContaining('Assignment saved'), findsNothing);
  });
  testWidgets(
    'same frame close callbacks fire once and clear old selection state',
    (tester) async {
      await show(tester);
      final close = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'Close'))
          .onPressed!;
      close();
      close();
      await tester.pumpAndSettle();
      expect(closed, 1);
      expect(find.byKey(ValueKey('instructor-${identity(2)}')), findsNothing);
      expect(repository.writes, isEmpty);
    },
  );
  testWidgets('close during invalidated pending read discards late reply', (
    tester,
  ) async {
    final pending = Completer<CoursePaymentInstructor?>();
    repository.pendingGet = pending;
    await show(tester, settle: false);
    auth.lock('device_revoked');
    await tester.pump();
    final close = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'Close'))
        .onPressed!;
    close();
    close();
    pending.complete(null);
    await tester.pumpAndSettle();
    expect(closed, 1);
    expect(repository.lists, isEmpty);
  });
  for (final action in ['Cancel', 'Confirm assignment']) {
    testWidgets('retained $action cannot pop an unrelated route above dialog', (
      tester,
    ) async {
      await show(tester);
      await select(tester, 2);
      await tap(tester, 'Assign instructor');
      final retained = action == 'Cancel'
          ? tester
                .widget<TextButton>(find.widgetWithText(TextButton, action))
                .onPressed!
          : tester
                .widget<FilledButton>(find.widgetWithText(FilledButton, action))
                .onPressed!;
      final navigator = Navigator.of(
        tester.element(find.byType(AlertDialog)),
        rootNavigator: true,
      );
      final unrelated = MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('Unrelated route')),
      );
      unawaited(navigator.push(unrelated));
      await tester.pumpAndSettle();
      retained();
      retained();
      await tester.pumpAndSettle();
      expect(unrelated.isCurrent, isTrue);
      expect(find.text('Unrelated route'), findsOneWidget);
      expect(repository.writes, isEmpty);
      expect(closed, 0);
      navigator.pop();
      await tester.pumpAndSettle();
      // Own dialog remains usable after the unrelated route is closed normally.
      await tap(tester, 'Cancel');
      expect(repository.writes, isEmpty);
      // A callback retained after disposal is also inert, not a notifier read.
      retained();
      await tester.pumpAndSettle();
      expect(closed, 0);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('raw private error is never rendered', (tester) async {
    repository.getError = StateError('SECRET phone 00000000000 recipient');
    await show(tester);
    expect(find.textContaining('SECRET'), findsNothing);
    expect(find.textContaining('00000000000'), findsNothing);
  });
  testWidgets(
    'small screen large text selection and scrollable dialog do not overflow',
    (tester) async {
      await show(tester, size: const Size(320, 568), scale: 2.5);
      await select(tester, 2);
      await tap(tester, 'Assign instructor');
      expect(tester.takeException(), isNull);
      await tap(tester, 'Cancel');
      await tap(tester, 'Close');
      await tap(tester, 'Discard selection');
      expect(tester.takeException(), isNull);
      expect(repository.writes, isEmpty);
    },
  );
}
