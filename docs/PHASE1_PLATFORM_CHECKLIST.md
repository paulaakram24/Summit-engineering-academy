# Phase 1 mobile platform checklist

Updated 2026-10-16. Development configuration only; runtime authentication and release readiness are not certified. This task owns only this checklist, `app/android/app/src/main/AndroidManifest.xml`, and `app/ios/Runner/Info.plist`. Backend setup belongs to the main agent; Dart authentication belongs to the auth UI agent. No builds, signing changes, external configuration, or pushes were performed.

## Native configuration implemented

| Item | Actual configuration |
| --- | --- |
| Development callback | `seaacademy-dev://auth/callback` |
| Android callback | Exported `.MainActivity`, existing `singleTop`; VIEW intent with DEFAULT/BROWSABLE, exact scheme `seaacademy-dev`, host `auth`, path `/callback` |
| Android network | INTERNET permission in the main manifest, available to all build variants |
| Android link ownership | Activity metadata `flutter_deeplinking_enabled=false` |
| Android backup | Application `android:allowBackup=false` |
| iOS callback | `CFBundleURLTypes` registers `seaacademy-dev`; iOS registers the scheme, not a host/path restriction |
| iOS link ownership | `FlutterDeepLinkingEnabled=false` |
| Android identity | Existing development placeholder `com.example.summit_academy`; namespace unchanged |
| iOS identity | Existing `com.example.summitAcademy`; plist still uses `$(PRODUCT_BUNDLE_IDENTIFIER)` |
| Signing / OS baseline | Existing Android release configuration uses debug signing; SDK levels follow Flutter. iOS deployment target is 15.0. No signing or identifier edits |

The Flutter flags follow [Flutter's plugin guidance](https://docs.flutter.dev/release/breaking-changes/deep-links-flag-change); [supabase_flutter](https://pub.dev/packages/supabase_flutter) uses `app_links` internally. The auth owner must use this exact redirect for OAuth and relevant email flows, initialize Supabase before auth interaction, and avoid a second callback consumer or duplicate code exchange. Validate the scheme, host and path before app navigation, particularly on iOS. Registration alone does not establish a session.

Custom schemes are appropriate for this development setup but are not exclusive to this app. Plan verified HTTPS App Links / Universal Links for production. Android filtering follows the [Android deep-link guide](https://developer.android.com/training/app-links/create-deeplinks); iOS registration follows [Apple's URL scheme guidance](https://developer.apple.com/documentation/xcode/defining-a-custom-url-scheme-for-your-app). No broad HTTP transport exceptions were added.

## Secure session storage handoff

- [ ] Auth owner: explicitly wire secure session persistence into Supabase initialization. A `flutter_secure_storage` dependency alone does not replace Supabase's default SharedPreferences persistence. Ensure logout clears stored sessions and failed/expired restoration returns safely to sign-in.
- [ ] Verify PKCE verifier persistence and cold-start completion; do not log callback query/fragment values, session tokens, or credentials.
- [ ] Android: verify resolved minimum SDK supports the selected storage version (11.2.0 requires API 23+). Auto Backup is disabled to reduce restored ciphertext/key mismatches. This also removes ordinary cloud app-data backup; server-backed data must resync after sign-in.
- [ ] Android 12+: test device-to-device transfer. `allowBackup=false` is not a universal D2D exclusion on all manufacturers. Explicit extraction/backup exclusion resources remain a follow-up outside this three-file scope. Do not claim transfer-proof storage.
- [ ] iOS owner on macOS: review the selected plugin's Keychain entitlement instructions and configure required entitlements/provisioning in a separately scoped change. No Runner entitlement file or `CODE_SIGN_ENTITLEMENTS` setting was found during inspection. This plist change does not configure Keychain access groups. Verify write/read/delete and session persistence on a signed device before declaring secure storage ready.
- [ ] Test logout, restart, upgrade, reinstall, locked-device behavior, and recovery from unavailable/invalid keys. Select Keychain accessibility deliberately; do not assume uninstall removes stored credentials.

Sources: [secure storage maintainer documentation](https://pub.dev/packages/flutter_secure_storage), [Android backup limitations](https://developer.android.com/identity/data/autobackup), and [Supabase custom LocalStorage](https://pub.dev/packages/supabase_flutter#custom-localstorage).

## User-required Google OAuth setup (not performed)

For the browser-based Supabase OAuth flow:

1. In the intended Google Cloud project, configure consent branding/audience and development test users. Request only the identity scopes needed for sign-in; Gmail sending does not require adding Gmail scopes to mobile login.
2. Create a Web application OAuth client. Copy the exact Supabase callback from its Google provider settings into Google's authorized redirect URIs (normally `https://<project-ref>.supabase.co/auth/v1/callback`). The mobile custom scheme is a separate return destination.
3. Enable Google's provider in the development Supabase project and enter the client ID and secret there. Keep the secret in backend settings/approved secret storage only.
4. Add exactly `seaacademy-dev://auth/callback` to Supabase Auth's redirect allowlist. Have the auth owner pass it as `redirectTo` (and the appropriate email redirect argument). Review Site URL and email templates so confirmation/recovery links use the intended return destination. Avoid broad wildcard allowlists.
5. Confirm successful login and cancellation with an allowed test user. A future native Google SDK flow needs its own platform client configuration; this task adds no native Google client IDs, certificate fingerprints, or reversed-client-ID scheme.

Sources: [Google provider setup](https://supabase.com/docs/guides/auth/social-login/auth-google), [mobile redirects](https://supabase.com/docs/guides/auth/native-mobile-deep-linking).

## User-required Gmail SMTP setup (not performed)

1. Use a dedicated development sender account with 2-Step Verification. If account policy permits, generate an app password for Supabase SMTP. Never use the ordinary Google account password or disable account protection. If app passwords are unavailable under organization/security policy, use an approved SMTP provider instead.
2. In Supabase Auth custom SMTP, configure `smtp.gmail.com`, port `587` with TLS/STARTTLS, full sender email as username, and the app password as SMTP password. Set the sender address to the authenticated mailbox (or a verified permitted alias) and sender name to SEA Academy. Do not enable POP just to send mail.
3. Enter the password only in protected server settings; never in Dart, plist/manifest, build defines, screenshots, source control, or chat. OAuth client secrets, service-role/secret Supabase keys, and SMTP passwords must never ship in the app. The app should receive only its project URL and publishable key (or legacy anon key where needed), backed by RLS.
4. Send a real confirmation and password-reset message to a controlled test account, check inbox/spam and return links, and review rate limits. Gmail is a development choice; assess delivery, quotas, and an appropriate transactional sender before production. Supabase's default mail service is restricted and unsuitable for production.
5. Revoke unused app passwords and rotate exposed ones. A Google account password change revokes app passwords, so update server configuration securely afterward.

Sources: [Google app passwords](https://support.google.com/accounts/answer/185833), [Gmail SMTP connection settings](https://support.google.com/mail/answer/7104828?hl=en-gb), [Supabase SMTP setup](https://supabase.com/docs/guides/auth/auth-smtp).

## Validation and remaining gates

- Static checks on Windows: parse both XML files, assert callback/flag/permission/backup values, and check whitespace/diff. These checks do not prove plugin registration, merged manifest behavior, secure persistence, or successful authentication.
- No build, simulator/emulator launch, device test, OAuth transaction, or email send was performed. Android runtime checks are possible on Windows with an installed artifact and emulator/device; they remain pending under this task's no-build constraint.
- iOS builds, Xcode/plist tooling, Simulator tests, signing/provisioning, Keychain behavior, and device callback delivery cannot be validated locally on Windows. Use macOS/Xcode and a signed iOS device for the final checks.

After installing a development artifact, test URL dispatch (these commands only open the app; they do not authenticate):

```powershell
adb shell am start -W -a android.intent.action.VIEW -c android.intent.category.BROWSABLE -d "seaacademy-dev://auth/callback" com.example.summit_academy
```

On macOS with a booted iOS Simulator:

```sh
xcrun simctl openurl booted 'seaacademy-dev://auth/callback'
```

- [ ] Repeat callback tests with the app terminated, backgrounded, and foregrounded; verify one completion, no duplicate navigation, and no acceptance of unrelated host/path URLs.
- [ ] Complete real Google sign-in, cancellation, expired/replayed callback, confirmation, and password recovery flows; verify session restoration and logout.
- [ ] Inspect the merged Android manifest and resolved SDK values when builds are authorized.
- [ ] Test HTTPS access on the oldest supported devices: the [Supabase TLS cipher retirement notice](https://supabase.com/changelog/cbc-tls-ciphers-deprecated) announces changes for November 10, 2026. Do not weaken TLS to accommodate old clients.
- [ ] Before any store release: replace development identifiers/callback plan in a separate approved scope, configure production signing, verify entitlements, privacy declarations, version/build numbers, symbols, internal release-artifact tests, rollout monitoring, and a forward-fix plan. Current configuration is not store-ready.
