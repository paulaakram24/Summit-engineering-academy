import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/auth/auth_controller.dart';
import 'package:summit_academy/auth/auth_panel.dart';
import 'package:summit_academy/auth/auth_repository.dart';
import 'package:summit_academy/main.dart';

import 'auth_fakes.dart';

void main() {
  late FakeAuthRepository repo;
  late AuthController auth;
  setUp(() {
    repo = FakeAuthRepository();
    auth = AuthController(repo);
  });
  tearDown(() async {
    auth.dispose();
    await repo.dispose();
  });
  Future<void> show(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: AuthPanel(controller: auth)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'secure startup failure has no interactive auth or protected screen',
    (tester) async {
      await tester.pumpWidget(const SummitApp(initializationFailed: true));
      await tester.drag(find.byType(ListView), const Offset(0, -600));
      await tester.pumpAndSettle();
      expect(find.textContaining('could not start securely'), findsOneWidget);
      expect(find.byType(TextFormField), findsNothing);
    },
  );
  testWidgets(
    'signup enforces 12 character password and profile length bounds',
    (tester) async {
      await tester.runAsync(auth.start);
      await show(tester);
      await tester.tap(find.text('Create an account'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'learner@example.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Name'),
        'x' * 121,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Phone'),
        '1' * 33,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'University'),
        'x' * 161,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'New password'),
        '12345678901',
      );
      await tester.ensureVisible(find.text('Create account'));
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();
      expect(find.text('Use at least 12 characters.'), findsOneWidget);
      expect(find.text('Use 1–120 characters for your name.'), findsOneWidget);
      expect(
        find.text('Use 1–160 characters for your university.'),
        findsOneWidget,
      );
      expect(repo.calls, isEmpty);
    },
  );
  testWidgets(
    'recovery takes priority over ready screen and validates password confirmation',
    (tester) async {
      repo.hasSession = true;
      await tester.runAsync(auth.start);
      await show(tester);
      expect(find.text('Student account'), findsOneWidget);
      repo.emit(SessionEvent.recovery);
      await tester.pumpAndSettle();
      expect(find.text('Choose a new password'), findsOneWidget);
      expect(find.text('Student account'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'New password'),
        'long-new-password',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm password'),
        'different',
      );
      await tester.tap(find.text('Update password'));
      await tester.pumpAndSettle();
      expect(find.text('Passwords do not match.'), findsOneWidget);
      expect(repo.calls, isNot(contains('password')));
    },
  );
  testWidgets('server admin role is displayed without a role selector', (
    tester,
  ) async {
    repo.hasSession = true;
    repo.accessContext = const AccessContext(
      'admin',
      '11111111-1111-4111-8111-111111111111',
    );
    await tester.runAsync(auth.start);
    await show(tester);
    expect(find.text('Administrator account'), findsOneWidget);
    expect(find.byType(DropdownButton<String>), findsNothing);
    await tester.tap(find.text('Edit profile'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Name'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Email'), findsNothing);
  });
}
