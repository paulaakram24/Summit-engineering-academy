import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:summit_academy/auth/oauth_browser_launcher.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('seaacademy/auth_browser');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final uri = Uri.parse('https://example.test/oauth?state=synthetic');
  late List<Uri> fallbackCalls;

  Future<bool> fallback(Uri value) async {
    fallbackCalls.add(value);
    return true;
  }

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    fallbackCalls = [];
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('Android native success sends the URL and skips fallback', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return true;
    });

    expect(await openOAuthBrowser(uri, launchBrowser: fallback), isTrue);
    expect(calls, hasLength(1));
    expect(calls.single.method, 'launchEphemeral');
    expect(calls.single.arguments, {'url': uri.toString()});
    expect(fallbackCalls, isEmpty);
  });

  test('Android unsupported uses conventional browser once', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => false);
    expect(await openOAuthBrowser(uri, launchBrowser: fallback), isTrue);
    expect(fallbackCalls, [uri]);
  });

  test('Android missing bridge uses conventional browser', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw MissingPluginException();
    });
    expect(await openOAuthBrowser(uri, launchBrowser: fallback), isTrue);
    expect(fallbackCalls, [uri]);
  });

  test('Android platform failure closes without fallback', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      throw PlatformException(code: 'launch_failed', message: uri.toString());
    });
    expect(await openOAuthBrowser(uri, launchBrowser: fallback), isFalse);
    expect(fallbackCalls, isEmpty);
  });

  test('Android null response closes without fallback', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await openOAuthBrowser(uri, launchBrowser: fallback), isFalse);
    expect(fallbackCalls, isEmpty);
  });

  for (final platform in TargetPlatform.values) {
    if (platform == TargetPlatform.android) continue;
    test('$platform skips native bridge', () async {
      debugDefaultTargetPlatformOverride = platform;
      var nativeCalls = 0;
      messenger.setMockMethodCallHandler(channel, (_) async {
        nativeCalls++;
        return true;
      });
      expect(await openOAuthBrowser(uri, launchBrowser: fallback), isTrue);
      expect(nativeCalls, 0);
      expect(fallbackCalls, [uri]);
    });
  }

  test('conventional browser false is preserved', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => false);
    expect(
      await openOAuthBrowser(uri, launchBrowser: (_) async => false),
      isFalse,
    );
  });

  test('conventional browser platform failure returns false', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => false);
    expect(
      await openOAuthBrowser(
        uri,
        launchBrowser: (_) async {
          throw PlatformException(code: 'launch_failed');
        },
      ),
      isFalse,
    );
  });
}
