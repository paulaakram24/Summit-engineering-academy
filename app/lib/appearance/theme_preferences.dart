import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract interface class ThemePreferenceStore {
  Future<String?> read();
  Future<void> write(String value);
}

/// Device-wide appearance only; independent of accounts and auth namespaces.
class SecureThemePreferenceStore implements ThemePreferenceStore {
  const SecureThemePreferenceStore();

  // An isolated key alone is insufficient on Android: the package's default
  // resetOnError recovery can clear its entire container, shared with auth.
  // Isolate data/config/wrapped keys/KeyStore aliases, and fail without reset or
  // algorithm migration. Auth retains its existing, untouched storage options.
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      storageNamespace: 'sea_appearance_v1',
      resetOnError: false,
      migrateOnAlgorithmChange: false,
      migrateWithBackup: false,
    ),
  );
  static const _key = 'sea.appearance.theme_mode.v1';

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String value) => _storage.write(key: _key, value: value);
}

class ThemePreferenceController extends ChangeNotifier {
  ThemePreferenceController({this.store}) {
    unawaited(_load());
  }

  final ThemePreferenceStore? store;
  ThemeMode _mode = ThemeMode.system;
  ThemeMode get mode => _mode;
  bool _disposed = false;
  bool _selected = false;
  bool _writing = false;
  ThemeMode? _queued;

  Future<void> _load() async {
    final storage = store;
    if (storage == null) return;
    try {
      final value = await storage.read();
      if (_disposed || _selected) return;
      final restored = switch (value) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      if (_mode != restored) {
        _mode = restored;
        notifyListeners();
      }
    } catch (_) {
      // Preference failure must not affect authentication or block rendering.
      // No raw storage errors or values are logged.
    }
  }

  void select(ThemeMode value) {
    if (_disposed) return;
    // Even explicitly selecting System must supersede a pending startup read.
    _selected = true;
    _mode = value;
    _queued = value;
    unawaited(_drainWrites());
    notifyListeners();
  }

  Future<void> _drainWrites() async {
    final storage = store;
    if (_writing || storage == null) return;
    _writing = true;
    try {
      // Never overlap physical writes or time them out: an older platform write
      // could otherwise complete after a newer one. Coalesce waiting choices to
      // the latest intent. A hung write blocks persistence, not in-memory UI.
      while (_queued != null) {
        final next = _queued!;
        _queued = null;
        try {
          await storage.write(next.name);
        } catch (_) {
          // Keep the in-memory choice; no saved confirmation or automatic retry.
        }
      }
    } finally {
      _writing = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // Already accepted write intents finish serially after disposal, without
    // notifying widgets. Native writes cannot safely be canceled. Late reads and
    // new selections are ignored; process termination cannot guarantee a flush.
    super.dispose();
  }
}
