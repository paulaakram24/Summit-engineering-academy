import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/auth/auth_controller.dart';
import 'package:summit_academy/auth/auth_repository.dart';

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

  test('fresh login registers once before profile; refresh and resume only validate', () async {
    await auth.start();
    await auth.signIn('learner@example.test', 'password');
    await auth.settled;
    expect(repo.calls, ['signIn', 'register', 'profile']);
    expect(auth.stage, AuthStage.ready);
    repo.emit(SessionEvent.signedIn);
    await auth.settled;
    repo.emit(SessionEvent.refreshed);
    await auth.settled;
    auth.suspend();
    expect(auth.profile, isNull);
    expect(auth.stage, AuthStage.checking);
    await auth.checkAccess();
    expect(repo.calls.where((call) => call == 'register').length, 1);
    expect(repo.calls.where((call) => call == 'access').length, 3);
  });
  test('restored session validates without registering', () async {
    repo.hasSession = true;
    await auth.start();
    expect(repo.calls, ['access', 'profile']);
    expect(auth.stage, AuthStage.ready);
  });
  test(
    'only session_not_registered permits interrupted registration recovery',
    () async {
      repo.hasSession = true;
      repo.accessError = const AccountFailure('session_not_registered');
      await auth.start();
      expect(repo.calls, ['access', 'register', 'profile']);
      await auth.checkAccess();
      expect(repo.calls.where((call) => call == 'register').length, 1);
      expect(auth.stage, AuthStage.blocked);
    },
  );
  for (final code in [
    'session_replaced',
    'account_disabled',
    'device_revoked',
    'session_device_mismatch',
    'unverified_or_invalid_session',
  ]) {
    test('$code closes restored access and never reclaims', () async {
      repo.hasSession = true;
      repo.accessError = AccountFailure(code);
      await auth.start();
      repo.emit(SessionEvent.refreshed);
      await auth.checkAccess();
      expect(repo.calls, isNot(contains('register')));
      expect(repo.calls, isNot(contains('profile')));
      expect(auth.stage, AuthStage.blocked);
      expect(auth.access, isNull);
    });
  }
  for (final code in ['active_session_exists', 'device_limit']) {
    test(
      '$code rejects new login using local signout without end_session',
      () async {
        repo.registrationError = AccountFailure(code);
        await auth.signIn('learner@example.test', 'password');
        await auth.settled;
        expect(repo.calls, ['signIn', 'register', 'localSignOut']);
        expect(auth.stage, AuthStage.blocked);
        expect(auth.profile, isNull);
        await auth.logout();
        expect(repo.calls, isNot(contains('end')));
      },
    );
  }
  test('Google incomplete profile gates learning space until saved', () async {
    repo.details = const AccountProfile(
      name: 'Google User',
      phone: '',
      university: '',
    );
    await auth.googleSignIn();
    repo.hasSession = true;
    repo.emit(SessionEvent.signedIn);
    await auth.settled;
    expect(auth.stage, AuthStage.completeProfile);
    await auth.saveProfile(
      const AccountProfile(
        name: 'Google User',
        phone: '+201234567890',
        university: 'Summit',
      ),
    );
    expect(auth.stage, AuthStage.ready);
    expect(repo.calls, [
      'google',
      'register',
      'profile',
      'access',
      'save',
      'access',
      'profile',
    ]);
  });
  test('profile access failure never exposes ready content', () async {
    repo.hasSession = true;
    repo.profileError = const AccountFailure('backend');
    await auth.start();
    expect(auth.stage, AuthStage.blocked);
    expect(auth.profile, isNull);
  });
  test(
    'complete Google user enters without repeating profile completion',
    () async {
      await auth.googleSignIn();
      repo.hasSession = true;
      repo.emit(SessionEvent.signedIn);
      await auth.settled;
      expect(auth.stage, AuthStage.ready);
      expect(repo.calls, ['google', 'register', 'profile']);
    },
  );
  test(
    'restored incomplete profile stays gated across refresh and resume',
    () async {
      repo.hasSession = true;
      repo.details = const AccountProfile(
        name: 'Google User',
        phone: '',
        university: 'Summit',
      );
      await auth.start();
      expect(auth.stage, AuthStage.completeProfile);
      repo.emit(SessionEvent.refreshed);
      await auth.settled;
      expect(auth.stage, AuthStage.completeProfile);
      auth.suspend();
      await auth.checkAccess();
      expect(auth.stage, AuthStage.completeProfile);
      expect(repo.calls, isNot(contains('save')));
      expect(repo.calls, isNot(contains('register')));
    },
  );
  final invalidProfiles = <String, AccountProfile>{
    'blank name': const AccountProfile(
      name: '   ',
      phone: '+201234567890',
      university: 'Summit',
    ),
    'long name': AccountProfile(
      name: 'x' * 121,
      phone: '+201234567890',
      university: 'Summit',
    ),
    for (final phone in [
      '',
      'not a phone',
      '-------',
      '+( ) -',
      '12 34 56',
      '1234567890123456',
      '123+456789',
    ])
      'invalid phone "$phone"': AccountProfile(
        name: 'Learner',
        phone: phone,
        university: 'Summit',
      ),
    'blank university': const AccountProfile(
      name: 'Learner',
      phone: '+201234567890',
      university: '   ',
    ),
    'long university': AccountProfile(
      name: 'Learner',
      phone: '+201234567890',
      university: 'x' * 161,
    ),
  };
  for (final entry in invalidProfiles.entries) {
    test(
      'controller rejects ${entry.key} without saving or losing completion form',
      () async {
        repo.hasSession = true;
        repo.details = const AccountProfile(
          name: 'Google User',
          phone: '',
          university: 'Summit',
        );
        await auth.start();
        final original = auth.profile;
        repo.calls.clear();
        await auth.saveProfile(entry.value);
        expect(repo.calls, isEmpty);
        expect(auth.stage, AuthStage.completeProfile);
        expect(auth.profile, same(original));
        expect(auth.message, entry.value.validationMessage);
        expect(auth.message, isNotNull);
        expect(auth.busy, isFalse);
      },
    );
    test('controller rejects ${entry.key} on programmatic signup', () async {
      await auth.start();
      await auth.signUp('learner@example.test', 'long-password', entry.value);
      expect(repo.calls, isEmpty);
      expect(auth.stage, AuthStage.signedOut);
      expect(auth.message, isNotNull);
    });
  }
  test('restored malformed phone cannot bypass completion gate', () async {
    repo.hasSession = true;
    repo.details = const AccountProfile(
      name: 'Learner',
      phone: '-------',
      university: 'Summit',
    );
    await auth.start();
    expect(auth.stage, AuthStage.completeProfile);
  });
  test(
    'formatted phone and trimmed profile fields can complete profile',
    () async {
      repo.hasSession = true;
      repo.details = const AccountProfile(
        name: 'Google User',
        phone: '',
        university: 'Summit',
      );
      await auth.start();
      await auth.saveProfile(
        const AccountProfile(
          name: ' Learner ',
          phone: ' +20 (123) 456-7890 ',
          university: ' Summit ',
        ),
      );
      expect(auth.stage, AuthStage.ready);
      expect(repo.calls, contains('save'));
    },
  );
  test('recovery wins over in-flight profile response and refresh', () async {
    repo.hasSession = true;
    repo.profileCompleter = Completer<AccountProfile>();
    final startup = auth.start();
    await Future<void>.delayed(Duration.zero);
    repo.emit(SessionEvent.recovery);
    repo.emit(SessionEvent.refreshed);
    expect(auth.stage, AuthStage.recovery);
    repo.profileCompleter!.complete(repo.details);
    await startup;
    await auth.settled;
    expect(auth.stage, AuthStage.recovery);
    expect(auth.profile, isNull);
    expect(repo.recovery, isTrue);
    await auth.changePassword('new-password');
    expect(auth.stage, AuthStage.signedOut);
    expect(repo.calls, isNot(contains('register')));
    expect(repo.calls, isNot(contains('end')));
  });
  test(
    'persisted recovery starts at new password with no access RPC',
    () async {
      repo.hasSession = true;
      repo.recovery = true;
      await auth.start();
      expect(auth.stage, AuthStage.recovery);
      expect(repo.calls, isEmpty);
      await auth.checkAccess();
      expect(repo.calls, isEmpty);
    },
  );
  test(
    'late access response after logout cannot restore protected state',
    () async {
      repo.hasSession = true;
      repo.accessCompleter = Completer<AccessContext>();
      final startup = auth.start();
      await Future<void>.delayed(Duration.zero);
      await auth.logout();
      repo.accessCompleter!.complete(FakeAuthRepository.context);
      await startup;
      expect(auth.stage, AuthStage.signedOut);
      expect(auth.profile, isNull);
    },
  );
  test('logout ends validated server session before local signout', () async {
    repo.hasSession = true;
    await auth.start();
    await auth.logout();
    expect(repo.calls, ['access', 'profile', 'end', 'localSignOut']);
  });
  test(
    'offline logout still clears local access and reports cleanup uncertainty',
    () async {
      repo.hasSession = true;
      await auth.start();
      repo.endError = const AccountFailure('connection');
      await auth.logout();
      expect(auth.stage, AuthStage.signedOut);
      expect(auth.profile, isNull);
      expect(auth.message, contains('could not be confirmed'));
    },
  );
  test('signup verification resend enforces deterministic cooldown', () async {
    auth.dispose();
    var now = DateTime(2026);
    auth = AuthController(repo, now: () => now);
    await auth.signUp('learner@example.test', 'password', repo.details);
    expect(auth.stage, AuthStage.verification);
    expect(auth.resendSeconds, 60);
    await auth.resend();
    expect(repo.calls, ['signUp']);
    now = now.add(const Duration(seconds: 60));
    await auth.resend();
    expect(repo.calls, ['signUp', 'resend']);
    expect(auth.resendSeconds, 60);
    await auth.verify('123456');
    await auth.settled;
    expect(auth.stage, AuthStage.ready);
  });
  test(
    'unknown access errors fail closed but retry only checks access',
    () async {
      repo.hasSession = true;
      repo.accessError = StateError('offline');
      await auth.start();
      expect(auth.stage, AuthStage.blocked);
      repo.accessError = null;
      await auth.checkAccess();
      expect(auth.stage, AuthStage.ready);
      expect(repo.calls, isNot(contains('register')));
    },
  );
}
