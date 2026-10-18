package com.example.summit_academy

import android.content.ActivityNotFoundException
import android.net.Uri
import androidx.browser.customtabs.CustomTabsClient
import androidx.browser.customtabs.CustomTabsIntent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "seaacademy/auth_browser")
            .setMethodCallHandler { call, result ->
                if (call.method != "launchEphemeral") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val uri = call.argument<String>("url")?.let(Uri::parse)
                if (uri == null || uri.scheme != "https" || uri.host.isNullOrEmpty() ||
                    uri.path != "/auth/v1/authorize" ||
                    uri.getQueryParameter("provider") != "google"
                ) {
                    result.error("browser", "Invalid sign-in request.", null)
                    return@setMethodCallHandler
                }
                try {
                    val provider = CustomTabsClient.getPackageName(this, null)
                    if (provider == null ||
                        !CustomTabsClient.isEphemeralBrowsingSupported(this, provider)
                    ) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    // A real, isolated browser session avoids Chrome's native
                    // ADDSESSION account-settings detour. Never use a WebView.
                    val tab = CustomTabsIntent.Builder()
                        .setEphemeralBrowsingEnabled(true)
                        .setShareState(CustomTabsIntent.SHARE_STATE_OFF)
                        .build()
                    tab.intent.setPackage(provider)
                    tab.launchUrl(this, uri)
                    result.success(true)
                } catch (_: ActivityNotFoundException) {
                    result.error("browser", "Unable to open sign-in browser.", null)
                } catch (_: SecurityException) {
                    result.error("browser", "Unable to open sign-in browser.", null)
                }
            }
    }
}
