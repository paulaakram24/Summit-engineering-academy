import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

abstract class SecretStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class PlatformSecretStore implements SecretStore {
  const PlatformSecretStore();
  static const _storage = FlutterSecureStorage();
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// The SDK owns session serialization; no plaintext preferences fallback.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage(this.store, this.namespace);
  final SecretStore store;
  final String namespace;
  void Function()? onFailure;
  String get _key => '$namespace.session';
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } catch (_) {
      onFailure?.call();
      rethrow;
    }
  }

  @override
  Future<void> initialize() => _guard(() async {
    await store.write('$namespace.probe', 'ok');
    if (await store.read('$namespace.probe') != 'ok') {
      throw StateError('Secure storage unavailable');
    }
    await store.delete('$namespace.probe');
  });
  @override
  Future<bool> hasAccessToken() =>
      _guard(() async => await store.read(_key) != null);
  @override
  Future<String?> accessToken() => _guard(() => store.read(_key));
  @override
  Future<void> persistSession(String persistSessionString) =>
      _guard(() => store.write(_key, persistSessionString));
  @override
  Future<void> removePersistedSession() => _guard(() => store.delete(_key));
}

class SecurePkceStorage extends GotrueAsyncStorage {
  SecurePkceStorage(this.store, this.namespace);
  final SecretStore store;
  final String namespace;
  @override
  Future<String?> getItem({required String key}) =>
      store.read('$namespace.pkce.$key');
  @override
  Future<void> setItem({required String key, required String value}) =>
      store.write('$namespace.pkce.$key', value);
  @override
  Future<void> removeItem({required String key}) =>
      store.delete('$namespace.pkce.$key');
}

class InstallationSecret {
  InstallationSecret(this.store, this.namespace);
  final SecretStore store;
  final String namespace;
  Future<String>? _pending;
  Future<String> get() => _pending ??= _load();
  Future<String> _load() async {
    final key = '$namespace.installation';
    final existing = await store.read(key);
    if (existing != null) {
      if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(existing)) {
        throw StateError('Invalid installation secret');
      }
      return existing;
    }
    final random = Random.secure();
    final value = List.generate(
      32,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await store.write(key, value);
    if (await store.read(key) != value) {
      throw StateError('Secure storage unavailable');
    }
    return value;
  }
}
