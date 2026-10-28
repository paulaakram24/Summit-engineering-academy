# Device-local appearance preference

Scope: preserve the existing System/Light/Dark selection across restarts. This is an independent roadmap 5.5 increment, not payment or identity functionality.

## Contract

- Store only one appearance value using the already pinned storage package, an isolated versioned key and an independent Android storageNamespace with resetOnError disabled. A key prefix alone is insufficient: the plugin's default container recovery can clear sibling authentication data. Keep authentication's existing options/data unchanged. Never enumerate, erase or mutate authentication keys.
  - Current implementation key: sea.appearance.theme_mode.v1; values are system, light and dark. No IDs, tokens or profile fields are stored here.
- Device-local choice, not a cross-account ownership/access property or cloud-synchronized profile.
- Start rendering with System immediately. A missing, malformed or unreadable value leaves System selected; preference I/O must not block account startup or lock identity.
- An explicit user selection takes effect in memory immediately. A delayed initial read cannot override it.
- Preserve physical write order so rapid selections cannot leave an older completed write last. Swallow storage failures without logging backend/plugin details or falsely announcing successful persistence. A failed/stalled persistence operation is not proof that a selection survives process death.
- Dispose safely: no notifications/setState after disposal. Tests must state which already requested writes finish; do not infer that a pending write is committed when the app process is killed.
  - Already accepted write intents finish serially even after widget/controller disposal; later reads/selections are ignored. This does not guarantee a flush through process termination.
- System continues following platform brightness; explicit Light/Dark does not. See [Flutter ThemeMode](https://api.flutter.dev/flutter/material/ThemeMode.html).
- Reuse the [pinned storage read/write API](https://pub.dev/packages/flutter_secure_storage/versions/11.2.0). Pinned local AndroidOptions/FlutterSecureStorageConfig/FlutterSecureStoragePlugin sources were inspected to verify namespace and error-reset behavior. No dependency upgrade, biometric prompt or authentication storage migration is part of this increment.

## Verification gates

Require injected-store unit/widget checks for all values, malformed/missing data, read/write failures, delayed read after choice, serialized rapid writes, disposal and platform brightness. Existing auth/catalog tests must remain green. Record actual full suite, formatting/analysis/build and artifact in PROJECT_STATUS.md when executed.

Native persistence is a separate acceptance gate: select an appearance, allow the write to settle, restart the same installed artifact without clearing data, verify restoration, and return to the original choice. No authentication logout, role/session reset or content publication is authorized for appearance testing. An Android debug check does not prove iOS or signed-release storage behavior.

## Verified development evidence — 2026-10-21

Mobile App Builder implemented the isolated store/controller and existing-selector integration. Mobile Release Engineer caught the initial shared-default-container recovery risk before acceptance; appearance now uses Android namespace sea_appearance_v1 with resetOnError, migrateOnAlgorithmChange and migrateWithBackup false. Authentication storage/options and dependencies remain unchanged.

Main verified all 678 app tests (26 new appearance cases), clean analysis, locked dependencies, 63-file zero-change formatting and configured Android debug build (8.7s). Channel mocks assert exact Android options and default-container auth-sentinel preservation on simulated read/write failures. These are not native KeyStore corruption/recovery tests. Final bounded source review found no remaining concrete blocker.

APK: 189079561 bytes, SHA-256 39884883155F65E223B4447D6B269A9FED6579E8E6C052796B7717060F041144. Installed with -r on existing emulator-5554; installed base.apk hash matched. Existing administrator identity remained present. Initial System selection was visually observed; selecting Dark changed the UI, then force-stop/relaunch restored Dark and the same administrator home. No role/session reset, credential inspection, data clearing, publication or backend mutation was needed. Original System selection was restored afterward; a second restart restored the light system appearance and System was visually highlighted in the selector. Menu dismissed afterward. Local evidence under E:/Android-prerequisites-Summit/sea-appearance-* includes personal account details and is not committed.

This accepts one retained Android emulator/debug environment, not Huawei/iOS/signed-release persistence or native corruption recovery. Backend was unchanged; the 814 database assertions belong to the fresh pre-push check of bb617fa, not a new appearance-specific database run. Appearance/README follow-up remains unpushed pending fresh owner approval.
