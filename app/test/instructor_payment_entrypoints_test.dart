import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/auth/auth_controller.dart';
import 'package:summit_academy/auth/auth_panel.dart';
import 'package:summit_academy/auth/auth_repository.dart';
import 'package:summit_academy/commerce/instructor_payment_repository.dart';
import 'package:summit_academy/content/admin_content_screen.dart';
import 'package:summit_academy/content/content_models.dart';
import 'package:summit_academy/main.dart';

import 'auth_fakes.dart';
import 'content_admin_screen_test.dart' show FakeContentRepository;
import 'instructor_payment_profile_panel_test.dart'
    show ProfilePanelFake, actor;

class SetupRepository extends ProfilePanelFake {
  int courseReads = 0, directoryReads = 0, assignmentWrites = 0;
  @override
  Future<CoursePaymentInstructor?> getCourseInstructor({
    required String actorId,
    required String courseId,
  }) async {
    courseReads++;
    return null;
  }

  @override
  Future<PaymentInstructorPage> listInstructors({
    required String actorId,
    PaymentInstructorCursor? after,
    int limit = 20,
  }) async {
    directoryReads++;
    return PaymentInstructorPage(
      items: [],
      hasMore: false,
      nextCursor: null,
      limit: limit,
      after: after,
    );
  }

  @override
  Future<CoursePaymentInstructor> setCourseInstructor(
    SetCoursePaymentInstructorRequest request,
  ) async {
    assignmentWrites++;
    throw StateError('This integration test must never write');
  }
}

void main() {
  late FakeAuthRepository accounts;
  late AuthController auth;
  late SetupRepository payments;
  late FakeContentRepository content;
  setUp(() async {
    accounts = FakeAuthRepository()
      ..hasSession = true
      ..accessContext = const AccessContext('admin', actor);
    auth = AuthController(accounts);
    await auth.start();
    payments = SetupRepository()..current = null;
    content = FakeContentRepository()
      ..courses = [
        Course(
          id: '33333333-3333-4333-8333-333333333333',
          title: 'Synthetic course',
          instructor: 'Display only',
          category: 'Engineering',
          level: '1',
          pricePiasters: 100,
        ),
      ];
  });
  tearDown(() async {
    auth.dispose();
    await accounts.dispose();
  });
  Future<void> showHome(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(
      SummitApp(
        authController: auth,
        contentRepository: content,
        instructorPaymentRepository: payments,
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Receiving payment details'),
      250,
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'configured SummitApp opens own setup and Back returns without writes',
    (tester) async {
      await showHome(tester);
      await tester.tap(find.text('Receiving payment details'));
      await tester.pumpAndSettle();
      expect(find.text('My receiving details'), findsOneWidget);
      expect(payments.reads, [actor]);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('My receiving details'), findsNothing);
      expect(find.text('Receiving payment details'), findsOneWidget);
      expect(payments.writes, isEmpty);
      expect(payments.assignmentWrites, 0);
    },
  );
  testWidgets(
    'course-management entry opens assignment and Close returns to list',
    (tester) async {
      await showHome(tester);
      await tester.ensureVisible(find.text('Manage courses'));
      await tester.tap(find.text('Manage courses'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Payment instructor'));
      await tester.pumpAndSettle();
      expect(find.text('Course instructor'), findsOneWidget);
      expect(find.text('No selectable instructors found.'), findsOneWidget);
      expect(payments.courseReads, 1);
      expect(payments.directoryReads, 1);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Payment instructor'), findsOneWidget);
      expect(payments.assignmentWrites, 0);
      expect(payments.writes, isEmpty);
    },
  );
  testWidgets('student has neither setup entry nor repository reads', (
    tester,
  ) async {
    accounts.accessContext = const AccessContext('student', actor);
    await tester.runAsync(auth.checkAccess);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AuthPanel(
            controller: auth,
            contentRepository: content,
            instructorPaymentRepository: payments,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Receiving payment details'), findsNothing);
    expect(find.text('Manage courses'), findsNothing);
    expect(payments.reads, isEmpty);
    expect(payments.courseReads, 0);
  });
  testWidgets('deleted course cannot open instructor assignment', (
    tester,
  ) async {
    content.courses = [
      Course(
        id: '33333333-3333-4333-8333-333333333333',
        title: 'Deleted fixture',
        instructor: 'Display',
        category: 'Engineering',
        level: '1',
        pricePiasters: 100,
        deletedAt: DateTime.utc(2026),
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: AdminContentScreen(
          repository: content,
          authController: auth,
          instructorPaymentRepository: payments,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final button = tester.widget<TextButton>(
      find.widgetWithText(TextButton, 'Payment instructor'),
    );
    expect(button.onPressed, isNull);
    expect(payments.courseReads, 0);
  });
}
