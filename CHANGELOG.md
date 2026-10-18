# Changelog

All notable changes to Summit Engineering Academy are recorded here. Dates use `YYYY-MM-DD`.

## Unreleased

### Fixed
- 2026-10-18: Owner completed fresh Google sign-in on Huawei, returned to SEA's mandatory profile form and saved successfully; direct device inspection confirmed the personalized welcome screen. Restart/logout and broader Phase 1 acceptance checks remain pending.
- 2026-10-18: Traced Huawei's Google white-screen/settings detour to Google's HTTP 204 ADDSESSION browser-account response. Added capability-checked isolated Chrome Custom Tabs with real-browser fallback; 89 tests, analysis and Android build passed, and update installed on Huawei. Diagnostic isolated tab rendered Google's sign-in webpage; fresh app-button/callback acceptance remains pending. Browser accounts and security settings were not changed.
- 2026-10-18: Google sign-in validates the SDK-generated S256 PKCE URL before launch and uses a browser view with external-browser fallback and explicit account selection. Actual phone authorization URLs and backend redirects are valid; Chrome's account-settings detour remains under investigation. An earlier missing-parameter diagnosis based on shortened accessibility address text was corrected. Final device OAuth acceptance remains pending.
- 2026-10-18: Restored configured Android debug builds on Windows using a physical Gradle cache on E:; documented the linked-cache Kotlin DSL failure. Added explicit local Java/cache/build-configuration options to the verification script. Configured app installed and visually checked on the Android emulator; live sign-in and Huawei acceptance remain pending.

### Added
- 2026-10-18: Provisioned the previously selected first administrator through the guarded server-only bootstrap with an audit event. Verified Huawei session/profile restoration and Administrator account display after app restart; hosted database regression passed 84/84 with fixture cleanup confirmed. Updated delivery documentation to ROADMAP.md's canonical phase numbering.
- 2026-10-18: Explicit mandatory profile completion after Google sign-in, with shared name/phone validation and regression coverage for incomplete profiles and programmatic submission. University remains required under the original registration requirements.
- 2026-10-18: Official Google G logo added to the Continue with Google button, using a white outlined background and unchanged authentication action.
- 2026-10-16: Phase 1 identity migrations, owner-only profiles, private roles/devices/session ledger, private closed storage buckets, and rollback-based access regression tests deployed/verified on development. Added server-only first-admin provisioning script and provider setup guides. Client authentication integration and device acceptance are in progress; no Phase 1 push approved.
- 2026-10-15: Phase 1.1 development project verified healthy after user creation; recorded non-secret project reference and region. Phase 0 hosted checks passed on commit 05965ee.
- Phase 0 local verification completed on physical Huawei Android 9; approval required before pushing remaining checks/docs and running hosted CI.
- 2026-10-15: Verified Android debug APK build and installation; documented E: tooling repair, local verification script and emulator runtime limitations.
- Local next-milestone change: GitHub workflow for locked dependencies, formatting, analysis and widget tests using Flutter 3.47.7 (remote execution pending approval).
- Branded Flutter welcome screen using the original logo, accessible scrolling layout, System/Light/Dark appearance selection, and two widget regression tests.
- 2026-10-14: Phased ROADMAP.md, independent requirements reconciliation, and generated Flutter Android/iOS starter in app/.
- Initial product requirements and implementation roadmap.
- Mobile-only Student and Admin scope.
- Mandatory project-status, README, changelog, audit, and security requirements.

### Decisions
- Supabase backend with PostgreSQL and Row Level Security.
- Private signed video streaming.
- Manual InstaPay/Vodafone Cash verification.
- Two-device account limit and simultaneous-login protection.
- Migrated the planned mobile framework from React Native + Expo + TypeScript to Flutter + Dart; application code is not yet changed.
