import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/auth/auth_callback_handler.dart';
import 'package:summit_academy/auth/auth_controller.dart';
import 'package:summit_academy/auth/auth_panel.dart';

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

  AuthCallbackHandler failingCallback({void Function()? onFailure}) =>
      AuthCallbackHandler(
        exchange: (_) async => throw StateError('synthetic-private-detail'),
        onStart: auth.suspend,
        onError: () {
          onFailure?.call();
          auth.lock('callback');
        },
      );

  test(
    'failed initial callback never registers or exposes error details',
    () async {
      final handler = failingCallback();
      await handler.receive(
        Uri.parse('seaacademy-dev://auth/callback?code=synthetic-private-code'),
      );
      await auth.settled;
      expect(auth.stage, AuthStage.blocked);
      expect(auth.profile, isNull);
      expect(auth.access, isNull);
      expect(repo.calls, isEmpty);
      expect(repo.hasSession, isFalse);
      expect(auth.message, AuthController.failureMessage('callback'));
      expect(auth.message, isNot(contains('synthetic-private')));
      expect(auth.message, isNot(contains('Check your connection')));
      expect(auth.message, contains('If your email is already confirmed'));
    },
  );

  test('duplicate failed return does not retry a consumed exchange', () async {
    var failures = 0;
    final handler = failingCallback(onFailure: () => failures++);
    final uri = Uri.parse('seaacademy-dev://auth/callback?error=access_denied');
    await handler.receive(uri);
    await handler.receive(uri);
    expect(failures, 1);
    expect(repo.calls, isEmpty);
    expect(auth.stage, AuthStage.blocked);
  });

  test(
    'failed link hides existing workspace without ending its session',
    () async {
      repo.hasSession = true;
      await auth.start();
      expect(auth.stage, AuthStage.ready);
      repo.calls.clear();
      await failingCallback().receive(
        Uri.parse('seaacademy-dev://auth/callback?error=access_denied'),
      );
      expect(auth.stage, AuthStage.blocked);
      expect(auth.profile, isNull);
      expect(auth.access, isNull);
      expect(repo.hasSession, isTrue);
      expect(repo.calls, isEmpty);
      await auth.checkAccess();
      expect(repo.calls, ['access', 'profile']);
      expect(auth.stage, AuthStage.ready);
    },
  );

  test(
    'successful callback retains normal admission and profile checks',
    () async {
      final handler = AuthCallbackHandler(
        exchange: (_) =>
            auth.signIn('learner@example.test', 'synthetic-password'),
        onStart: auth.suspend,
        onError: () => auth.lock('callback'),
      );
      await handler.receive(
        Uri.parse('seaacademy-dev://auth/callback?code=synthetic-success'),
      );
      await auth.settled;
      expect(auth.stage, AuthStage.ready);
      expect(repo.calls, ['signIn', 'register', 'profile']);
      expect(auth.message, isNull);
    },
  );

  testWidgets(
    'failed-link guidance allows fresh password login without claiming verification',
    (tester) async {
      await tester.runAsync(auth.start);
      auth.lock('callback');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(child: AuthPanel(controller: auth)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(AuthController.failureMessage('callback')),
        findsOneWidget,
      );
      expect(find.text('Account access unavailable'), findsOneWidget);
      expect(find.text('Log out'), findsNothing);
      await tester.ensureVisible(find.text('Back to sign in'));
      await tester.tap(find.text('Back to sign in'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Email'), findsOneWidget);
      expect(
        find.text(AuthController.failureMessage('callback')),
        findsNothing,
      );
      expect(repo.calls, ['localSignOut']);
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'),
        'learner@example.test',
      );
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Password'),
        'synthetic-password',
      );
      final signInButton = find.widgetWithText(FilledButton, 'Sign in');
      await tester.ensureVisible(signInButton);
      await tester.runAsync(() async {
        await tester.tap(signInButton);
        await auth.settled;
      });
      await tester.pumpAndSettle();
      expect(auth.stage, AuthStage.ready);
      expect(repo.calls, ['localSignOut', 'signIn', 'register', 'profile']);
      expect(auth.message, isNull);
      expect(find.text('Student account'), findsOneWidget);
    },
  );
}
