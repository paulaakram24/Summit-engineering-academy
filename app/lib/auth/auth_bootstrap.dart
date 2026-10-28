import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'auth_controller.dart';
import 'auth_callback_handler.dart';
import 'secure_auth_storage.dart';
import 'supabase_auth_repository.dart';

class AuthBuildConfig {
  const AuthBuildConfig({
    this.url = const String.fromEnvironment('SUPABASE_URL'),
    this.publishableKey = const String.fromEnvironment(
      'SUPABASE_PUBLISHABLE_KEY',
    ),
  });
  final String url;
  final String publishableKey;
  bool get absent => url.isEmpty && publishableKey.isEmpty;
  bool get valid {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        uri.query.isEmpty &&
        uri.fragment.isEmpty &&
        publishableKey.startsWith('sb_publishable_') &&
        publishableKey.length > 20;
  }
}

class AuthRuntime {
  AuthRuntime(this.controller, this.repository, this.links);
  final AuthController controller;
  final SupabaseAuthRepository repository;
  final StreamSubscription<Uri> links;
  Future<void> dispose() async {
    await links.cancel();
    controller.dispose();
    await repository.dispose();
  }
}

Future<AuthRuntime> initializeAuth(
  AuthBuildConfig config, {
  SecretStore store = const PlatformSecretStore(),
}) async {
  if (!config.valid) {
    throw StateError('Invalid authentication configuration');
  }
  final namespace = 'sea.${Uri.parse(config.url).host}';
  final storage = SecureSessionStorage(store, namespace);
  await Supabase.initialize(
    url: config.url,
    publishableKey: config.publishableKey,
    debug: false,
    authOptions: FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
      localStorage: storage,
      pkceAsyncStorage: SecurePkceStorage(store, namespace),
      // Install our listener before consuming the initial callback so recovery
      // events cannot be lost during SDK initialization.
      detectSessionInUri: false,
    ),
  );
  final repository = SupabaseAuthRepository(
    Supabase.instance.client,
    store,
    namespace,
  );
  final controller = AuthController(repository);
  storage.onFailure = () => controller.lock('storage');
  final appLinks = AppLinks();
  final callbacks = AuthCallbackHandler(
    exchange: repository.handleCallback,
    onStart: controller.suspend,
    onError: () => controller.lock('callback'),
  );
  final links = appLinks.uriLinkStream.listen(
    callbacks.receive,
    onError: (Object _) => controller.lock('callback'),
  );
  try {
    final initial = await appLinks.getInitialLink();
    if (initial != null) {
      await callbacks.receive(initial);
    }
    await callbacks.settled;
    await controller.settled;
    if (!callbacks.received) {
      await controller.start();
    }
    return AuthRuntime(controller, repository, links);
  } catch (_) {
    await links.cancel();
    controller.dispose();
    await repository.dispose();
    rethrow;
  }
}
