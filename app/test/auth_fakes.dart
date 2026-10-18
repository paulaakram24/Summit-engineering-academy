import 'dart:async';

import 'package:summit_academy/auth/auth_repository.dart';
import 'package:summit_academy/auth/secure_auth_storage.dart';

class MemorySecrets implements SecretStore {
  final values = <String, String>{};
  bool fail = false;
  @override
  Future<String?> read(String key) async {
    if (fail) {
      throw StateError('unavailable');
    }
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    if (fail) {
      throw StateError('unavailable');
    }
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    if (fail) {
      throw StateError('unavailable');
    }
    values.remove(key);
  }
}

class FakeAuthRepository implements AuthRepository {
  final changes = StreamController<SessionEvent>.broadcast(sync: true);
  final calls = <String>[];
  @override
  bool hasSession = false;
  @override
  String? email = 'learner@example.test';
  bool recovery = false;
  Object? accessError;
  Object? registrationError;
  Object? profileError;
  Object? saveError;
  Object? endError;
  Completer<AccessContext>? accessCompleter;
  Completer<AccountProfile>? profileCompleter;
  AccountProfile details = const AccountProfile(
    name: 'Learner',
    phone: '+201234567890',
    university: 'Summit',
  );
  static const context = AccessContext(
    'student',
    '11111111-1111-4111-8111-111111111111',
  );
  AccessContext accessContext = context;
  void emit(SessionEvent event) {
    changes.add(event);
  }

  @override
  Stream<SessionEvent> get events => changes.stream;
  @override
  Future<bool> recoveryPending() async => recovery;
  @override
  Future<void> setRecoveryPending(bool value) async {
    recovery = value;
  }

  @override
  Future<void> signIn(String email, String password) async {
    calls.add('signIn');
    hasSession = true;
    emit(SessionEvent.signedIn);
  }

  @override
  Future<void> signUp(
    String email,
    String password,
    AccountProfile profile,
  ) async {
    calls.add('signUp');
    details = profile;
  }

  @override
  Future<void> googleSignIn() async {
    calls.add('google');
  }

  @override
  Future<void> resendVerification(String email) async {
    calls.add('resend');
  }

  @override
  Future<void> verifyEmail(String email, String code) async {
    calls.add('verify');
    hasSession = true;
    emit(SessionEvent.signedIn);
  }

  @override
  Future<void> sendRecovery(String email) async {
    calls.add('sendRecovery');
  }

  @override
  Future<void> updatePassword(String password) async {
    calls.add('password');
    emit(SessionEvent.restored);
  }

  @override
  Future<AccessContext> registerDevice() async {
    calls.add('register');
    if (registrationError != null) {
      throw registrationError!;
    }
    return accessContext;
  }

  @override
  Future<AccessContext> getAccessContext() async {
    calls.add('access');
    if (accessError != null) {
      throw accessError!;
    }
    return accessCompleter == null
        ? accessContext
        : await accessCompleter!.future;
  }

  @override
  Future<AccountProfile> fetchProfile() async {
    calls.add('profile');
    if (profileError != null) {
      throw profileError!;
    }
    return profileCompleter == null ? details : await profileCompleter!.future;
  }

  @override
  Future<void> saveProfile(AccountProfile profile) async {
    calls.add('save');
    if (saveError != null) {
      throw saveError!;
    }
    details = profile;
  }

  @override
  Future<void> endSession() async {
    calls.add('end');
    if (endError != null) {
      throw endError!;
    }
  }

  @override
  Future<void> signOut() async {
    calls.add('localSignOut');
    hasSession = false;
    emit(SessionEvent.signedOut);
  }

  @override
  Future<void> dispose() => changes.close();
}
