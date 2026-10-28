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
        find.widgetWithText(TextFormField, 'Name (required)'),
        'x' * 121,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Phone (required)'),
        '1' * 33,
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'University (required)'),
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
  testWidgets('recovery displays the current repository email', (tester) async {
    repo.hasSession = true;
    repo.recovery = true;
    repo.email = 'learner@example.test';
    await tester.runAsync(auth.start);
    await show(tester);

    expect(auth.stage, AuthStage.recovery);
    expect(
      find.text('Resetting password for learner@example.test'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextFormField, 'Email'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'New password'), findsOneWidget);
    expect(
      find.widgetWithText(TextFormField, 'Confirm password'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Update password'),
          )
          .onPressed,
      isNotNull,
    );
    expect(repo.calls, isEmpty);
  });

  for (final entry in <String, String?>{
    'null': null,
    'empty': '',
    'blank': '   ',
    'invalid': 'not-an-email',
  }.entries) {
    testWidgets(
      'recovery with ${entry.key} email blocks password entry and allows cancel',
      (tester) async {
        repo.hasSession = true;
        repo.recovery = true;
        repo.email = entry.value;
        await tester.runAsync(auth.start);
        await show(tester);

        expect(auth.stage, AuthStage.recovery);
        expect(
          find.text(
            'Recovery account could not be verified. Cancel and request a new reset link.',
          ),
          findsOneWidget,
        );
        expect(find.textContaining('Resetting password for'), findsNothing);
        expect(find.byType(TextFormField), findsNothing);
        expect(find.text('Update password'), findsNothing);
        final cancel = find.widgetWithText(FilledButton, 'Cancel and sign out');
        expect(cancel, findsOneWidget);
        expect(tester.widget<FilledButton>(cancel).onPressed, isNotNull);
        expect(repo.calls, isEmpty);

        await tester.runAsync(() async {
          await tester.tap(cancel);
          await auth.settled;
        });
        await tester.pumpAndSettle();

        expect(auth.stage, AuthStage.signedOut);
        expect(repo.hasSession, isFalse);
        expect(repo.recovery, isFalse);
        expect(repo.calls, ['localSignOut']);
      },
    );
  }

  testWidgets('email changes during recovery clear both password inputs', (
    tester,
  ) async {
    repo.hasSession = true;
    repo.recovery = true;
    repo.email = 'learner@example.test';
    await tester.runAsync(auth.start);
    await show(tester);

    final password = find.widgetWithText(TextFormField, 'New password');
    final confirm = find.widgetWithText(TextFormField, 'Confirm password');
    await tester.enterText(password, 'synthetic-password-one');
    await tester.enterText(confirm, 'synthetic-password-two');
    expect(
      tester.widget<TextFormField>(password).controller!.text,
      'synthetic-password-one',
    );
    expect(
      tester.widget<TextFormField>(confirm).controller!.text,
      'synthetic-password-two',
    );

    repo.email = 'another-learner@example.test';
    repo.emit(SessionEvent.recovery);
    await tester.pumpAndSettle();

    expect(auth.stage, AuthStage.recovery);
    expect(
      find.text('Resetting password for another-learner@example.test'),
      findsOneWidget,
    );
    expect(
      find.text('Resetting password for learner@example.test'),
      findsNothing,
    );
    expect(tester.widget<TextFormField>(password).controller!.text, isEmpty);
    expect(tester.widget<TextFormField>(confirm).controller!.text, isEmpty);
    expect(repo.calls, isEmpty);
  });

  testWidgets(
    'stale recovery Update callback clears inputs without updating after email changes without notification',
    (tester) async {
      repo.hasSession = true;
      repo.recovery = true;
      await tester.runAsync(auth.start);
      await show(tester);

      final password = find.widgetWithText(TextFormField, 'New password');
      final confirm = find.widgetWithText(TextFormField, 'Confirm password');
      const syntheticPassword = 'synthetic-matching-password';
      await tester.enterText(password, syntheticPassword);
      await tester.enterText(confirm, syntheticPassword);
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextFormField>(password).controller!.text,
        syntheticPassword,
      );
      expect(
        tester.widget<TextFormField>(confirm).controller!.text,
        syntheticPassword,
      );
      final staleUpdate = tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Update password'),
          )
          .onPressed!;

      // Change the live account without emitting an event or pumping a rebuild.
      repo.email = 'another-learner@example.test';
      expect(
        find.text('Resetting password for learner@example.test'),
        findsOneWidget,
      );
      staleUpdate();
      await tester.pumpAndSettle();

      expect(repo.calls, isEmpty);
      expect(auth.stage, AuthStage.recovery);
      expect(tester.widget<TextFormField>(password).controller!.text, isEmpty);
      expect(tester.widget<TextFormField>(confirm).controller!.text, isEmpty);
      expect(
        find.text('Resetting password for another-learner@example.test'),
        findsOneWidget,
      );
    },
  );

  testWidgets('session vanishes during recovery hides password entry', (
    tester,
  ) async {
    repo.hasSession = true;
    repo.recovery = true;
    await tester.runAsync(auth.start);
    await show(tester);
    expect(find.byType(TextFormField), findsNWidgets(2));

    repo.hasSession = false;
    repo.emit(SessionEvent.recovery);
    await tester.pumpAndSettle();

    expect(auth.stage, AuthStage.recovery);
    expect(
      find.text(
        'Recovery account could not be verified. Cancel and request a new reset link.',
      ),
      findsOneWidget,
    );
    expect(find.textContaining('Resetting password for'), findsNothing);
    expect(find.byType(TextFormField), findsNothing);
    expect(find.text('Update password'), findsNothing);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Cancel and sign out'),
          )
          .onPressed,
      isNotNull,
    );
    expect(repo.calls, isEmpty);
  });

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
    expect(
      find.widgetWithText(TextFormField, 'Name (required)'),
      findsOneWidget,
    );
    expect(find.widgetWithText(TextFormField, 'Email'), findsNothing);
  });
  testWidgets('Google login requires reviewing and saving mandatory details', (
    tester,
  ) async {
    await tester.runAsync(auth.start);
    await show(tester);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();
    expect(repo.calls, ['google']);
    repo.details = const AccountProfile(
      name: 'Google User',
      phone: '',
      university: 'Summit',
    );
    repo.hasSession = true;
    await tester.runAsync(() async {
      repo.emit(SessionEvent.signedIn);
      await auth.settled;
    });
    await tester.pumpAndSettle();
    expect(find.text('Complete your profile'), findsOneWidget);
    expect(
      find.textContaining('Review any details filled in from Google'),
      findsOneWidget,
    );
    expect(find.text('Student account'), findsNothing);
    final name = find.widgetWithText(TextFormField, 'Name (required)');
    final phone = find.widgetWithText(TextFormField, 'Phone (required)');
    final university = find.widgetWithText(
      TextFormField,
      'University (required)',
    );
    expect(tester.widget<TextFormField>(name).controller!.text, 'Google User');
    expect(university, findsOneWidget);
    expect(repo.calls, isNot(contains('save')));
    await tester.ensureVisible(find.text('Save profile'));
    await tester.tap(find.text('Save profile'));
    await tester.pumpAndSettle();
    expect(
      find.text('Enter a valid phone number with 7–15 digits.'),
      findsOneWidget,
    );
    expect(repo.calls, isNot(contains('save')));

    await tester.enterText(name, '   ');
    await tester.enterText(phone, '-------');
    await tester.enterText(university, '   ');
    await tester.ensureVisible(find.text('Save profile'));
    await tester.tap(find.text('Save profile'));
    await tester.pumpAndSettle();
    expect(find.text('Use 1–120 characters for your name.'), findsOneWidget);
    expect(
      find.text('Enter a valid phone number with 7–15 digits.'),
      findsOneWidget,
    );
    expect(
      find.text('Use 1–160 characters for your university.'),
      findsOneWidget,
    );
    expect(auth.stage, AuthStage.completeProfile);
    expect(repo.calls, isNot(contains('save')));

    await tester.enterText(name, 'Reviewed Name');
    await tester.enterText(phone, '+20 (123) 456-7890');
    await tester.enterText(university, 'Summit');
    await tester.ensureVisible(find.text('Save profile'));
    await tester.runAsync(() async {
      await tester.tap(find.text('Save profile'));
      await Future<void>.delayed(Duration.zero);
      await auth.settled;
    });
    await tester.pumpAndSettle();
    expect(find.text('Welcome, Reviewed Name'), findsOneWidget);
    expect(find.text('Complete your profile'), findsNothing);
    expect(repo.calls.where((call) => call == 'save'), hasLength(1));
  });
  testWidgets(
    'complete returning user does not see mandatory completion form',
    (tester) async {
      repo.hasSession = true;
      await tester.runAsync(auth.start);
      await show(tester);
      expect(find.text('Student account'), findsOneWidget);
      expect(find.text('Complete your profile'), findsNothing);
      expect(find.text('Save profile'), findsNothing);
      expect(repo.calls, isNot(contains('save')));
    },
  );
}
