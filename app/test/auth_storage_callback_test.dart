import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/auth/auth_bootstrap.dart';
import 'package:summit_academy/auth/auth_callback_handler.dart';
import 'package:summit_academy/auth/auth_controller.dart';
import 'package:summit_academy/auth/auth_repository.dart';
import 'package:summit_academy/auth/secure_auth_storage.dart';

import 'auth_fakes.dart';

void main() {
  test('configuration has no defaults and rejects partial, insecure and secret key configs', () {
    expect(const AuthBuildConfig().absent, isTrue);
    expect(const AuthBuildConfig(url: 'https://example.test').valid, isFalse);
    expect(
      const AuthBuildConfig(
        url: 'http://example.test',
        publishableKey: 'sb_publishable_test_public',
      ).valid,
      isFalse,
    );
    expect(
      const AuthBuildConfig(
        url: 'https://example.test',
        publishableKey: 'sb_secret_not_for_clients',
      ).valid,
      isFalse,
    );
    expect(
      const AuthBuildConfig(
        url: 'https://example.test',
        publishableKey: 'sb_publishable_test_public',
      ).valid,
      isTrue,
    );
  });
  test(
    'SDK session and PKCE adapters exclusively use the secret store',
    () async {
      final secrets = MemorySecrets();
      final session = SecureSessionStorage(secrets, 'sea.test');
      await session.initialize();
      expect(await session.hasAccessToken(), isFalse);
      await session.persistSession('synthetic-session');
      expect(await session.hasAccessToken(), isTrue);
      expect(await session.accessToken(), 'synthetic-session');
      final pkce = SecurePkceStorage(secrets, 'sea.test');
      await pkce.setItem(key: 'verifier', value: 'synthetic-verifier');
      expect(await pkce.getItem(key: 'verifier'), 'synthetic-verifier');
      await pkce.removeItem(key: 'verifier');
      await session.removePersistedSession();
      expect(secrets.values, isEmpty);
    },
  );
  test(
    'secure storage failures propagate and close controller access',
    () async {
      final secrets = MemorySecrets()..fail = true;
      final session = SecureSessionStorage(secrets, 'sea.test');
      var failures = 0;
      session.onFailure = () => failures++;
      await expectLater(session.initialize(), throwsStateError);
      await expectLater(
        session.persistSession('synthetic-session'),
        throwsStateError,
      );
      expect(failures, 2);
      expect(secrets.values, isEmpty);
    },
  );
  test('installation secret is 64hex, stable, separate from session and serialized across calls', () async {
    final secrets = MemorySecrets();
    final installation = InstallationSecret(secrets, 'sea.test');
    final values = await Future.wait([installation.get(), installation.get()]);
    expect(values.first, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(values.first, values.last);
    expect(await InstallationSecret(secrets, 'sea.test').get(), values.first);
    final storage = SecureSessionStorage(secrets, 'sea.test');
    await storage.persistSession('synthetic-session');
    await storage.removePersistedSession();
    expect(await installation.get(), values.first);
    expect(
      await InstallationSecret(MemorySecrets(), 'sea.test').get(),
      isNot(values.first),
    );
  });
  test('corrupt installation secrets fail instead of silently replacing the device', () async {
    final secrets = MemorySecrets()..values['sea.test.installation'] = 'broken';
    await expectLater(
      InstallationSecret(secrets, 'sea.test').get(),
      throwsStateError,
    );
  });
  test(
    'duplicate initial and stream callback exchange once even while pending',
    () async {
      final pending = Completer<void>();
      var calls = 0;
      var errors = 0;
      var starts = 0;
      final handler = AuthCallbackHandler(
        exchange: (_) async {
          calls++;
          await pending.future;
        },
        onStart: () => starts++,
        onError: () => errors++,
      );
      final uri = Uri.parse('seaacademy-dev://auth/callback?code=synthetic');
      final first = handler.receive(uri);
      final duplicate = handler.receive(uri);
      pending.complete();
      await Future.wait([first, duplicate]);
      await handler.receive(uri);
      expect(calls, 1);
      expect(starts, 1);
      expect(errors, 0);
    },
  );
  test(
    'callback cache is bounded and unrelated callback addresses are ignored',
    () async {
      var calls = 0;
      final handler = AuthCallbackHandler(
        capacity: 2,
        exchange: (_) async {
          calls++;
        },
        onStart: () {},
        onError: () {},
      );
      await handler.receive(Uri.parse('other://auth/callback?code=x'));
      for (final code in ['a', 'b', 'c', 'a']) {
        await handler.receive(
          Uri.parse('seaacademy-dev://auth/callback?code=$code'),
        );
      }
      expect(calls, 4);
    },
  );
  test(
    'initial recovery callback routes before any access or registration RPC',
    () async {
      final repo = FakeAuthRepository();
      final auth = AuthController(repo);
      final handler = AuthCallbackHandler(
        exchange: (_) async {
          repo.hasSession = true;
          repo.emit(SessionEvent.recovery);
        },
        onStart: auth.suspend,
        onError: () => auth.lock('auth'),
      );
      await handler.receive(
        Uri.parse('seaacademy-dev://auth/callback?code=recovery'),
      );
      await auth.settled;
      expect(auth.stage, AuthStage.recovery);
      expect(repo.calls, isEmpty);
      expect(repo.recovery, isTrue);
      auth.dispose();
      await repo.dispose();
    },
  );
  test('malformed server access context is rejected', () {
    expect(
      () => AccessContext.fromJson({'role': 'owner', 'device_id': 'x'}),
      throwsA(isA<AccountFailure>()),
    );
    expect(
      () => AccessContext.fromJson({'role': 'admin', 'device_id': ''}),
      throwsA(isA<AccountFailure>()),
    );
  });
}
