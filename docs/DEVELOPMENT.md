# Development

The app is in app/. Verified SDK: Flutter 3.47.7 / Dart 3.13.5.
On this PC use C:/src/flutter/bin/flutter.bat explicitly until duplicate Flutter installations are consolidated.

## Local verification

From the repository root in PowerShell:

```powershell
./scripts/check.ps1 -Flutter C:/src/flutter/bin/flutter.bat
./scripts/check.ps1 -Flutter C:/src/flutter/bin/flutter.bat -BuildAndroid
```

Checks stop on the first failure. The optional build creates app/build/app/outputs/flutter-apk/app-debug.apk.
Run dart format --output=none --set-exit-if-changed lib test from app/ to check formatting.

## Device testing

Use flutter devices to select an Android emulator or USB-debugging device, then flutter run -d DEVICE_ID from app/.
On this PC, set ANDROID_AVD_HOME=E:/Android/avd and use Summit_Pixel_API_37. The default C: emulator could not start because of insufficient space.
NDK 28.2.13676358, app/build and Gradle 9.3.1 transforms are junctions to E:/Android-prerequisites-Summit. Keep that drive available. Do not remove these targets during cleanup.
Use E:/Android-prerequisites-Summit/temp for TEMP/TMP during large builds. Android SDK remains at C:/Users/Paula/AppData/Local/Android/Sdk; Java currently comes from Android Studio's bundled JBR. CI uses JDK 17.
Exercise appearance selection, scroll the welcome screen, and check large system text.
iOS requires a macOS build host; do not report iOS verification based on Windows tests.

## Configuration and credentials

Phase 0 runs without backend accounts or secrets. No production credentials belong in Dart defines or bundled assets.
Public backend configuration will be introduced with authentication in phase 1. Server credentials remain server-side.
The generated com.example.summit_academy identifier is development-only until release identifiers are confirmed.
Launcher icons and release signing are not finalized.

## Approval

Each milestone includes status updates and test results. Push only after user approval for that milestone.
The GitHub checks workflow is prepared locally and cannot be verified on GitHub until its push is approved.
