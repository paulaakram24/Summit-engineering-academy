import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_repository.dart';
import 'secure_auth_storage.dart';

const authRedirect = 'seaacademy-dev://auth/callback';

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this.client, this.store, this.namespace)
    : installation = InstallationSecret(store, namespace) {
    _subscription = client.auth.onAuthStateChange.listen(
      (state) {
        final event = switch (state.event) {
          AuthChangeEvent.passwordRecovery => SessionEvent.recovery,
          AuthChangeEvent.signedOut => SessionEvent.signedOut,
          AuthChangeEvent.tokenRefreshed => SessionEvent.refreshed,
          AuthChangeEvent.signedIn when _interactive => SessionEvent.signedIn,
          _ => SessionEvent.restored,
        };
        if (event == SessionEvent.signedIn || event == SessionEvent.recovery) {
          _interactive = false;
        }
        _events.add(event);
        if ((event == SessionEvent.signedIn ||
                event == SessionEvent.recovery) &&
            _authenticationEvent?.isCompleted == false) {
          _authenticationEvent!.complete();
        }
      },
      onError: (Object _) {
        _events.addError(const AccountFailure('connection'));
      },
    );
  }
  final SupabaseClient client;
  final SecretStore store;
  final String namespace;
  final InstallationSecret installation;
  final _events = StreamController<SessionEvent>.broadcast(sync: true);
  late final StreamSubscription<AuthState> _subscription;
  bool _interactive = false;
  Completer<void>? _authenticationEvent;
  @override
  Stream<SessionEvent> get events => _events.stream;
  @override
  bool get hasSession => client.auth.currentSession != null;
  @override
  String? get email => client.auth.currentUser?.email;
  @override
  Future<bool> recoveryPending() async =>
      await store.read('$namespace.recovery') == 'true';
  @override
  Future<void> setRecoveryPending(bool value) => value
      ? store.write('$namespace.recovery', 'true')
      : store.delete('$namespace.recovery');

  Future<T> _call<T>(Future<T> Function() action) async {
    try {
      return await action().timeout(const Duration(seconds: 20));
    } on AuthException catch (e) {
      throw AccountFailure(e.code ?? 'auth');
    } on PostgrestException catch (e) {
      // Whitelist known server codes; never display database details or tokens.
      for (final code in [
        'device_limit',
        'session_replaced',
        'unverified_account',
        'active_session_exists',
        'session_not_registered',
        'unverified_or_invalid_session',
        'account_disabled',
        'device_revoked',
        'session_device_mismatch',
      ]) {
        if (e.message.contains(code) || e.code == code) {
          throw AccountFailure(code);
        }
      }
      throw const AccountFailure('backend');
    }
  }

  Future<void> _authenticate(Future<void> Function() action) async {
    _interactive = true;
    final delivered = Completer<void>();
    _authenticationEvent = delivered;
    try {
      await _call(action);
      // Auth's public stream is asynchronous. Keep the fresh-login intent
      // until its event has been delivered, including password recovery.
      if (hasSession) {
        await delivered.future.timeout(const Duration(seconds: 5));
      }
    } finally {
      _interactive = false;
      _authenticationEvent = null;
    }
  }

  @override
  Future<void> signUp(String email, String password, AccountProfile profile) =>
      _authenticate(() async {
        await client.auth.signUp(
          email: email,
          password: password,
          data: profile.toJson(),
          emailRedirectTo: authRedirect,
        );
      });
  @override
  Future<void> signIn(String email, String password) => _authenticate(() async {
    await client.auth.signInWithPassword(email: email, password: password);
  });
  @override
  Future<void> googleSignIn() => _call(() async {
    final launched = await client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: authRedirect,
      authScreenLaunchMode: LaunchMode.externalApplication,
    );
    if (!launched) {
      throw const AccountFailure('browser');
    }
  });
  Future<void> handleCallback(Uri uri) async {
    if (uri.scheme != 'seaacademy-dev' ||
        uri.host != 'auth' ||
        uri.path != '/callback') {
      return;
    }
    await _authenticate(() async {
      await client.auth.getSessionFromUrl(uri);
    });
  }

  @override
  Future<void> resendVerification(String email) => _call(() async {
    await client.auth.resend(
      type: OtpType.signup,
      email: email,
      emailRedirectTo: authRedirect,
    );
  });
  @override
  Future<void> verifyEmail(String email, String code) =>
      _authenticate(() async {
        await client.auth.verifyOTP(
          email: email,
          token: code,
          type: OtpType.signup,
        );
      });
  @override
  Future<void> sendRecovery(String email) => _call(
    () => client.auth.resetPasswordForEmail(email, redirectTo: authRedirect),
  );
  @override
  Future<void> updatePassword(String password) => _call(() async {
    await client.auth.updateUser(UserAttributes(password: password));
  });
  @override
  Future<AccessContext> registerDevice() => _call(
    () async => AccessContext.fromJson(
      await client.rpc(
        'register_device',
        params: {
          'p_device_token': await installation.get(),
          'p_label': 'SEA Academy ${defaultTargetPlatform.name}',
        },
      ),
    ),
  );
  @override
  Future<AccessContext> getAccessContext() => _call(
    () async => AccessContext.fromJson(await client.rpc('get_access_context')),
  );
  @override
  Future<AccountProfile> fetchProfile() => _call(() async {
    final user = client.auth.currentUser;
    if (user == null) {
      throw const AccountFailure('session_replaced');
    }
    final row = await client
        .from('profiles')
        .select('id,name,phone,university,created_at')
        .eq('id', user.id)
        .single();
    return AccountProfile.fromJson(row);
  });
  @override
  Future<void> saveProfile(AccountProfile profile) => _call(() async {
    await getAccessContext();
    final user = client.auth.currentUser;
    if (user == null) {
      throw const AccountFailure('session_replaced');
    }
    final row = await client
        .from('profiles')
        .update(profile.toJson())
        .eq('id', user.id)
        .select('id,name,phone,university,created_at')
        .single();
    if (row['id'] != user.id) {
      throw const AccountFailure('invalid_access');
    }
  });
  @override
  Future<void> endSession() => _call(() async {
    await client.rpc('end_session');
  });
  @override
  Future<void> signOut() =>
      _call(() => client.auth.signOut(scope: SignOutScope.local));
  @override
  Future<void> dispose() async {
    await _subscription.cancel();
    await _events.close();
  }
}
