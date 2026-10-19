# Summit Engineering Academy

Summit Engineering Academy is a mobile learning app where students browse courses, purchase individual sessions or complete courses, access protected videos and materials, submit assignments, and track progress. Admins manage students, courses, sessions, content, payments, access, notifications, and audit logs.

## Planned stack

- Flutter stable, Dart
- Flutter Material 3 with a responsive Student/Admin design system
- GoRouter or equivalent typed navigation
- Supabase Auth and PostgreSQL
- Supabase Storage for controlled files and payment receipts
- Supabase Edge Functions for privileged workflows
- Cloudflare Stream for private video playback (selected; integration pending)
- Firebase Cloud Messaging/APNs through a Flutter push-notification package

## Brand asset

The supplied official logo is stored at `assets/sea-logo.png`. Use it as the primary app logo and source artwork for the splash screen, authentication screens, profile/admin branding, and app-store icon variants. Preserve the navy, teal, and gold palette; do not redraw or alter the logo artwork without approval.

## Local setup

Development backend is deployed. Google sign-in, mandatory profile save, first-admin provisioning and session restoration after app restart are verified on Huawei. **Manage courses** provides administrator course/session lists, create/edit, exact EGP prices, ordering and recoverable delete/restore with confirmation. Administrator lifecycle and private course-cover selection/readback/replacement/removal/cleanup were accepted on Huawei using an owner-approved temporary draft on 2026-10-19; it was never published and is now soft-deleted/recoverable. Server authorization and audit remain mandatory; restore returns to draft. See `docs/PHASE2_DEVICE_ACCEPTANCE.md`; student-side, iOS and signed release-artifact acceptance remain open. Materials, student catalog, purchases and playback remain unfinished. Email delivery/recovery and remaining identity acceptance also stay open. `ROADMAP.md` is the canonical phase sequence; `PROJECT_STATUS.md` records evidence.

From `app/`, use the pinned Flutter SDK and run:

```powershell
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter run --dart-define-from-file=config/development.json
```

The development JSON contains only a public URL and publishable key. Never add server secrets to it. Without these build defines the app deliberately shows the unconfigured foundation screen. Configuration errors fail closed.

On the current Windows development PC, the verified configured build/check command from the repository root is:

```powershell
./scripts/check.ps1 -Flutter 'C:/src/flutter/bin/flutter.bat' -BuildAndroid -DartDefineFile config/development.json -GradleUserHome 'E:/Android-prerequisites-Summit/gradle-physical' -JavaHome 'C:/Program Files/Microsoft/jdk-17.0.20.101-hotspot'
```

These machine-specific paths are command arguments, not global settings. The script restores its environment after completion. Use ordinary physical directories for the Gradle cache on this pinned Gradle 9.3.1 Windows setup: linked cache paths caused Kotlin DSL failures consistent with [Gradle issue 36483](https://github.com/gradle/gradle/issues/36483). Tests, analysis, configured APK build, and emulator installation passed on 2026-10-18. See PROJECT_STATUS.md for remaining live-auth and physical-device checks.

Backend migrations are under `supabase/migrations/`; hosted dev migration versions match local filenames. The owner connected Supabase to GitHub; inspect that integration before any push/deployment, and do not create paid branches. SQL regression instructions are in `docs/PHASE1_DATABASE_TESTS.md`; execute the entire rollback-based suite, not fragments. Backend CI passed on checkpoint `975bf67` using a disposable local backend. The hosted development suite passed 84/84 again on 2026-10-18 after administrator provisioning; follow-up changes remain local and require fresh push approval.

Owner setup: `docs/GOOGLE_SIGN_IN_SETUP.md` and `docs/PHASE1_PLATFORM_CHECKLIST.md`. Architecture and access controls: `docs/PHASE1_BACKEND.md`. Administrator provisioning is deliberately server-only and requires the owner to register/verify first.

Content contracts and upload boundaries: `docs/CONTENT_CONTRACT.md`. Content denial/constraint tests: `docs/PHASE2_DATABASE_TESTS.md` and `supabase/tests/phase2_content.sql`. Development migration `20261018154932_phase2_content_core` matches hosted history. The expanded backend workflow runs both identity and content suites after the next approved push; hosted execution of this new workflow is not yet verified.

Private covers (2026-10-19): see `docs/COURSE_COVER_DESIGN.md` and deployed migration `20261019015308_phase2_private_covers`. Picker/private preview UI and administrator real binary workflow are accepted on Huawei; both temporary uploads were cleaned through Storage API and the original logo retained. Historical cover/content/identity database suites passed 267 assertions. Latest app analysis, all 310 tests, formatting and configured Android build pass, including 105 admin-material client checks after actor-bound retry correction. The workflow additionally runs `supabase/tests/phase2_covers.sql`. Follow-up changes remain unpushed pending fresh approval. Approved student-discovery/library improvements are specified in `docs/STUDENT_EXPERIENCE.md`, not yet implemented.

Admin materials backend (2026-10-19): migration `20261019154009_phase2_admin_materials.sql` is deployed to development; main verified 163 material assertions and the 267 existing regressions (430 total), with fixture cleanup confirmed. The backend workflow includes `supabase/tests/phase2_materials.sql`; hosted CI requires an approved push. Actor-bound client retries are verified; material editor UI acceptance remains open. See `docs/PHASE2_MATERIALS.md`; this does not enable student file/video access.

Verified local toolchain: Flutter 3.47.7 and Dart 3.13.5 at C:/src/flutter. Application source is in app/. Run flutter pub get, flutter analyze, flutter test, and flutter run from app/. Required environment variables must be listed in .env.example when integrations are added; secrets must never be committed.

Expected setup sequence:

1. Install dependencies.
2. Create/configure the Supabase project.
3. Apply migrations and seed only non-sensitive development data.
4. Configure storage buckets, auth providers, Edge Functions, and video-provider credentials.
5. Start the Flutter app on an Android emulator or connected device.
6. Run type checks, linting, unit tests, integration tests, and a security checklist.

## Security

All authorization must be enforced server-side with Supabase RLS and Edge Functions. The client must never decide whether a student owns access. Payment approval, access grants, signed video URLs, device registration, and admin actions must be audited.

## Documentation

- [PROJECT_STATUS.md](PROJECT_STATUS.md) tracks delivery state and decisions.
- [CHANGELOG.md](CHANGELOG.md) records user-visible and security-relevant changes.
- The master implementation instructions are in `MASTER_BUILD_PROMPT.md`.
- `REFERENCE_ANALYSIS.md` records permitted product lessons from the Leader_Academy public App Store listing.

## Recommended downloads before implementation

- Git for repository work.
- Flutter stable SDK, including its bundled Dart SDK and DevTools.
- Android Studio and an Android emulator, plus Xcode on a macOS machine for iOS builds.
- CocoaPods on macOS for iOS dependencies.
- Supabase CLI for migrations and local development.
- A Mux or Cloudflare Stream account for private video playback.
- Accounts/credentials for email, push notifications, and any approved WhatsApp notification provider.

Do not download production credentials, paid media, or payment secrets into the repository. Create `.env.example` only; real values belong in local secret storage or CI/CD secrets.

## Migration decision and risks

The plan is now Flutter/Dart instead of React Native/Expo/TypeScript. Flutter gives one consistent rendering layer across Android and iOS, strong control over the colorful branded UI, and a straightforward release path. The tradeoff is replacing the JavaScript/Expo toolchain and selecting Flutter equivalents for navigation, secure storage, media playback, notifications, analytics, and testing.

Before coding, verify `flutter doctor`, Android emulator/device builds, and an iOS Simulator build on macOS. Confirm package compatibility for Supabase, secure storage, video playback, file picking, push notifications, Google sign-in, and signed playback URLs. Keep payment verification server-side in Supabase Edge Functions; Flutter only submits requests and displays states.

### Exact next steps

1. Install Flutter stable and run `flutter doctor -v`.
2. Install Android Studio, SDK tools, an emulator, and accept Android licenses.
3. On macOS, install Xcode and CocoaPods, then validate an iOS simulator build.
4. Create the Flutter project structure without implementing business features.
5. Add Supabase configuration through secret-safe environment handling.
6. Prototype authentication and role loading only.
7. Validate private video playback and signed URL expiry on both platforms.
8. Validate the two-device/session policy and manual-payment state machine.
9. Only after these checks, begin the first vertical slice.

## Current prerequisite audit

Already available on the Windows PC: Git, Android Studio, OpenJDK 17, VS Code, GitHub CLI, and Android SDK directories. Not yet verified: Flutter/Dart, Supabase CLI, ADB/emulator launch, Cloudflare Stream, Gmail SMTP, Meta WhatsApp Cloud API, Supabase project, and store accounts. iOS builds cannot be verified until a Mac with Xcode is available.
