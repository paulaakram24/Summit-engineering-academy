# Summit Engineering Academy

## Current verified source milestone — 2026-10-28

Owner-approved milestone prepared for push: administrator PDF/TXT quarantine uploads,
instructor receiving-detail setup, saved appearance settings, and authentication
improvements. Fresh checks passed **1,035 Flutter tests**, **122 offline Node tests**,
clean analysis, 86-file formatting, locked dependencies and an Android debug build
(113.4s). Independent Agency-guided reviews completed; personal test-mailbox
identities were removed from pending public notes.

Checkout, payment approval, trusted file attachment and student delivery remain
closed. No production APK release is implied. GitHub CI for this source milestone
is pending; the earlier 992 database assertions are historical, not a new local run.
The physical Huawei admin restart passed without ending any existing session.
Its latest-build update is deferred while the phone reports1% battery.
See [project status](PROJECT_STATUS.md) for current evidence and open gates.

## Earlier verification notes

The following checkpoint notes retain their original scope and historical results;
their statements about unpushed work describe those earlier increments.

Latest form fix: opening the keyboard no longer refreshes credential/profile
entry forms on the tested emulator. Real background and protected-workspace
access checks remain active. All1,030serial app tests, analysis and formatting
passed; installedE7DEFAndroidbuild retained keyboard focus and unsaved typing.
The synthetic draft was cleared without saving. Owner profile completion and
other Phase1gates remain open. See [focus verification](docs/PHASE1_FORM_FOCUS.md).
Nothing in this increment was pushed.

Latest recovery improvement: the reset form identifies the active account
before password entry and blocks unidentified sessions. Main passed1,025app
tests, analysis, formatting and the Android build. Installed3FE756artifact
visibly showed the test account; owner privately completed password update and
fresh login. Normal student logout/server termination and signed-out restart
also passed. Remaining callback/multi-device/physical gates keep Phase1open;
no password was entered by the agent and no push was performed.
Exact evidence is in [project status](PROJECT_STATUS.md).

Latest app correction: uncertain upload/status checks no longer falsely claim
an empty history. Four new regression tests pass; final local checks passed
**1,017 app tests**, clean analysis, locked dependencies and formatting.
Android debug build succeeded in57.6s; later614040update/launch-only acceptance
on the emulator retained Administrator home with matching installed hash.
Native uncertain-upload acceptance remains open; nothing is pushed.
Live scanning/student delivery remain
closed. See [project status](PROJECT_STATUS.md) for the exact artifact and gates.

Latest offline groundwork: [material byte-observation prototype](tools/material-validation/README.md)
passes122local tests and syntax checks on Node25.7.0. This is synthetic-stream
hashing/bounds testing only, not an isolated scanner or server-file validation.
All outcomes deny readiness; live delivery remains closed. New Node22 CI is
defined but unrun remotely; no push or app/backend change in this increment.
The reviewed [worker isolation acceptance plan](docs/MATERIAL_WORKER_ISOLATION_ACCEPTANCE.md)
records the missing local Linux runtime and remaining safeguards; no installation,
scanner or live file read was enabled.

SEA is a Flutter mobile learning app for students and administrators. The planned product supports courses, individual sessions, editable admin-selected session bundles, protected learning materials, assignments and manually verified payments.

### Earlier repository checkpoints

Approved milestone `bb617fa` was pushed on 2026-10-21 with Paula as author. Fresh local verification passed **652 app tests**, **814 database assertions**, clean analysis/formatting and a configured Android debug build. GitHub outcomes are recorded separately in [PROJECT_STATUS.md](PROJECT_STATUS.md); local results do not imply remote success.

Both GitHub workflows for bb617fa passed. A separate local appearance increment now remembers System/Light/Dark across restarts: 678 app tests, analysis/formatting and Android build passed; bounded emulator persistence accepted and original System selection restored. This follow-up is **not pushed** and does not close broader device/release gates. See [appearance verification](docs/APPEARANCE_PREFERENCES.md).

Latest unpushed setup checkpoint: private instructor receiving profiles/course binding are deployed to development, with earlier 893-assertion database evidence. Actor-pinned transport and administrator receiving-details/course-assignment screens are now connected: 834 app tests, clean analysis/formatting and configured Android debug build. Receiving fields are number and recipient name only; same-course bundles must inherit one instructor. Real-value/native mutation acceptance, bundle enforcement and changed-destination review transitions remain open. No real receiving values, course bindings or orders were created during setup acceptance. See [instructor setup](docs/INSTRUCTOR_PAYMENTS.md) and exact artifact/device evidence in [status](PROJECT_STATUS.md).

Latest local upload increment: administrator PDF/TXT file selection and private quarantine-upload controls are integrated. The new development backend passed all eleven suites / 992 assertions before and after deployment; the integrated app passed 978 tests, analysis and formatting. Final build/native acceptance is recorded separately in status. Files are not yet validated, attached, published or available to students. See [material uploads](docs/MATERIAL_FILE_UPLOADS.md). Nothing in this increment is pushed.

Follow-up: native synthetic TXT selection, confirmation cancellation and discard/reopen accepted without cloud upload. An abnormal-provider deadline/cancellation fix passed **1001 app tests**, analysis and formatting; its exact build/device evidence is tracked in status. [Quarantine cleanup design](docs/MATERIAL_UPLOAD_CLEANUP_DESIGN.md) is design only: no deletion or automatic retention is enabled.

2026-10-24 bounded native acceptance: an isolated synthetic draft received an actual194-byte TXT upload through the normal app; server quarantine status/Storage metadata matched and reopening freshly listed it. Anonymous object access was denied. One private synthetic object is retained/tracked; trusted validation/student delivery and broader acceptance remain open. See [binary acceptance](docs/MATERIAL_UPLOAD_BINARY_ACCEPTANCE.md). No new push.

Latest fresh checks: **1013 app tests**, **992 database assertions**, clean analysis/locked dependencies and84-file formatting. The12new tests exercise the full picker/navigation/admission hierarchy. This test-only follow-up changes no production code; the installed8AC77artifact remains the accepted TXT-transfer debug build, not a production release.

Later restart acceptance on8AC77 restored Administrator home and freshly loaded uploaded statuses. Current inventory is **two** distinct private194-byte TXT objects (388declared-observed bytes), both unvalidated; the additional operation predates that read-only run and was preserved without attribution. [Trusted validation/attachment design](docs/MATERIAL_VALIDATION_DESIGN.md) defines the next boundaries but enables no scanner, read access or student delivery. No new suite/build run or push is implied by this documentation/native follow-up.

Implemented: Google sign-in and required name/phone/university profile, server-controlled roles and device/session admission, administrator course/session/material metadata authoring, private covers, published catalog/search/filters, and account-backed Saved courses with confirmed unavailable-reference cleanup. Huawei/emulator acceptance is limited to the exact flows/artifacts recorded in status.

Private pending-order contracts and read-only history transport are verified, but **creation is disabled** and no order UI is connected. Checkout, receipt upload, approval, refunds, entitlements and protected learning remain unfinished. A pending intent is not payment received or learning access.

Initial release direction is direct Android installation with student-selected InstaPay/Vodafone Cash, transaction screenshot and administrator verification of actual received funds. No production APK has been released. Signing, identifiers, download/update hosting and release acceptance remain open; public-store/iPhone distribution is deferred.

See [ROADMAP.md](ROADMAP.md) for phases and [morning decisions](docs/MORNING_QUESTIONS.md) for the resolved commerce policies and remaining acceptance gates. Historical checkpoints belong in status/changelog rather than duplicated README summaries.

## Stack and assets

- Flutter 3.47.7 / bundled Dart 3.13.5, Material 3 and feature-oriented modules under `app/lib/`.
- Supabase Auth, PostgreSQL/RLS and private Storage; migrations/tests under `supabase/`.
- Server-side privileged workflows, never mobile service-role credentials.
- Cloudflare Stream selected; private video integration pending. Push/WhatsApp integration also pending.
- Official logo: `assets/sea-logo.png`. Preserve its navy/teal/gold artwork; do not redraw without approval.

## Run locally

Use the pinned Flutter SDK and an Android SDK/emulator or connected debugging-enabled phone. From `app/`:

```powershell
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter run --dart-define-from-file=config/development.json
```

The machine-local development JSON contains only `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`: the intended project's HTTPS URL and publishable key. Never put backend secrets there or overwrite current configuration unnecessarily. Missing defines show the foundation screen; invalid configuration fails closed.

On this Windows PC, the accepted configured check/build command from the repository root is:

```powershell
./scripts/check.ps1 -Flutter 'C:/src/flutter/bin/flutter.bat' -BuildAndroid -DartDefineFile config/development.json -GradleUserHome 'E:/Android-prerequisites-Summit/gradle-physical' -JavaHome 'C:/Program Files/Microsoft/jdk-17.0.20.101-hotspot'
```

Use the established E: temporary directory when C: space is constrained. Cache/JDK paths are command arguments, not global settings; the script restores its Gradle environment. Debug output is `app/build/app/outputs/flutter-apk/app-debug.apk`, not a signed production release.

iOS build/runtime acceptance requires macOS/Xcode/CocoaPods and remains unverified. Do not infer it from source inspection or Android checks.

## Backend checks

Development migration history matches `supabase/migrations/`. Inspect the owner's GitHub/Supabase integration before deployment; do not create paid branches or reset hosted data for tests.

[Backend CI](.github/workflows/backend-checks.yml) starts a disposable backend and runs eleven SQL suites with stop-on-error: identity, admin sessions, content, covers, materials, upload quarantine, catalog, bookmarks, cleanup, closed pending orders and private instructor-payment setup. Execute each complete file on one connection, including transaction/rollback, not fragments. Hosted rollback evidence does not prove fresh-reset or real parallel-transaction behavior; the new setup/upload workflow steps have not run remotely before an approved push.

The [October 30 grant-notice assessment](docs/SUPABASE_OCTOBER_2026_NOTICE.md) explains explicit grants and RLS as separate boundaries. Never apply blanket permissions to make a table reachable. Order creation remains closed at both entry points, including to service_role.

## Security and operating rules

Authorization, active admission, authoritative roles and ownership are enforced server-side. Students have two registered installations and one active application session maximum; enabled admins are exempt. Never alter the owner's role/session just to advance testing.

Private covers and saved courses grant no paid-material access. Do not fabricate ownership from pending intents. Actual funds verification and audited approval/access integration are still required.

Keep passwords, SMTP app passwords, OAuth secrets, service keys, signing keys, tokens and full OAuth URLs out of source/logs/chat. Use approved local/backend/CI secret storage. Parent-project `sources/` files are read-only references.

Every additional milestone push needs fresh explicit owner approval after testing. A debug build or repository push is not production-release approval.

## Documentation

- [Status](PROJECT_STATUS.md), [roadmap](ROADMAP.md), [changelog](CHANGELOG.md): current evidence, phases and history.
- [Master build prompt](MASTER_BUILD_PROMPT.md), [requirements](REQUIREMENTS_CORRECTIONS.md): implementation instructions and clarifications.
- [Google setup](docs/GOOGLE_SIGN_IN_SETUP.md), [platform checklist](docs/PHASE1_PLATFORM_CHECKLIST.md), [backend architecture](docs/PHASE1_BACKEND.md): setup and identity/access gates.
- [Catalog](docs/CATALOG_IMPLEMENTATION.md), [Saved courses](docs/SAVED_COURSES_DESIGN.md), [device acceptance](docs/PHASE2_DEVICE_ACCEPTANCE.md): discovery boundaries and actual native evidence.
- [Material editor](docs/ADMIN_MATERIAL_EDITOR.md): admin metadata authoring, not student delivery.
- [Pending-order foundation](docs/PENDING_ORDERS_FOUNDATION.md), [entitlement design](docs/ENTITLEMENTS_DESIGN.md): staged contracts, not implemented payment/access flows.
- [Audit handoff](docs/PHASE3_STAGED_AUDIT_HANDOFF.md): independent Claude Code instructions, not an executed audit.
- [Student experience](docs/STUDENT_EXPERIENCE.md), [reference analysis](REFERENCE_ANALYSIS.md): permitted product lessons, not copied implementation.
