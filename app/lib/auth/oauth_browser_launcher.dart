import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart' as browser;

const _authBrowser = MethodChannel('seaacademy/auth_browser');

/// Opens OAuth in an Android ephemeral tab when available, or a real browser.
/// [launchBrowser] substitutes the conventional browser path in unit tests.
Future<bool> openOAuthBrowser(
  Uri uri, {
  Future<bool> Function(Uri uri)? launchBrowser,
}) async {
  try {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      try {
        final launched = await _authBrowser.invokeMethod<bool>(
          'launchEphemeral',
          {'url': uri.toString()},
        );
        if (launched != false) return launched == true;
      } on MissingPluginException {
        // Older hosts and tests may not register the native bridge.
      }
    }
    return await (launchBrowser ?? _launchConventionalBrowser)(uri);
  } on PlatformException {
    // Do not retry a failed launch or expose OAuth URLs in diagnostics.
    return false;
  }
}

Future<bool> _launchConventionalBrowser(Uri uri) async {
  final browserView = await browser.supportsLaunchMode(
    browser.LaunchMode.inAppBrowserView,
  );
  return browser.launchUrl(
    uri,
    mode: browserView
        ? browser.LaunchMode.inAppBrowserView
        : browser.LaunchMode.externalApplication,
  );
}
