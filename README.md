# Summit Engineering Academy

Summit Engineering Academy is a mobile learning app where students browse courses, purchase individual sessions or complete courses, access protected videos and materials, submit assignments, and track progress. Admins manage students, courses, sessions, content, payments, access, notifications, and audit logs.

## Planned stack

- Flutter stable, Dart
- Flutter Material 3 with a responsive Student/Admin design system
- GoRouter or equivalent typed navigation
- Supabase Auth and PostgreSQL
- Supabase Storage for controlled files and payment receipts
- Supabase Edge Functions for privileged workflows
- Mux or Cloudflare Stream for private video playback
- Firebase Cloud Messaging/APNs through a Flutter push-notification package

## Brand asset

The supplied official logo is stored at `assets/sea-logo.png`. Use it as the primary app logo and source artwork for the splash screen, authentication screens, profile/admin branding, and app-store icon variants. Preserve the navy, teal, and gold palette; do not redraw or alter the logo artwork without approval.

## Local setup

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
