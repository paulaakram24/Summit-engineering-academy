# Changelog

All notable changes to Summit Engineering Academy are recorded here. Dates use `YYYY-MM-DD`.

## Unreleased

### Verified follow-up
- 2026-10-19: Administrator per-session material editor with draft assignment/link/media-placeholder authoring, private detail loading, recoverable delete/restore, identity/lifecycle invalidation, unsaved-change guards and conservative uncertain-save refresh recovery. All 355 app tests, analysis/format and Android debug build passed; controlled Huawei assignment/link/placeholder persistence and lifecycle accepted. Temporary parent soft-deleted/recoverable, no publication or student media delivery. This UI increment remains unpushed pending fresh approval.
- 2026-10-19: Approved foundation checkpoint pushed as 5fa6d4a; remote Flutter and Backend workflows both passed. Those checks precede the separate material UI increment.

### Fixed
- 2026-10-19: Retained material mutations are bound to the originating authenticated actor and use a pinned request token with identity revalidation. Cross-account/signed-out retries fail safely, while exact same-actor retries remain supported. Added 25 regressions (105 material tests; all 310 app tests), clean analysis/formatting and Android build passed. Material editor UI remains pending.
- 2026-10-18: Owner completed fresh Google sign-in on Huawei, returned to SEA's mandatory profile form and saved successfully; direct device inspection confirmed the personalized welcome screen. Restart/logout and broader Phase 1 acceptance checks remain pending.
- 2026-10-18: Traced Huawei's Google white-screen/settings detour to Google's HTTP 204 ADDSESSION browser-account response. Added capability-checked isolated Chrome Custom Tabs with real-browser fallback; 89 tests, analysis and Android build passed, and update installed on Huawei. Diagnostic isolated tab rendered Google's sign-in webpage; fresh app-button/callback acceptance remains pending. Browser accounts and security settings were not changed.
- 2026-10-18: Google sign-in validates the SDK-generated S256 PKCE URL before launch and uses a browser view with external-browser fallback and explicit account selection. Actual phone authorization URLs and backend redirects are valid; Chrome's account-settings detour remains under investigation. An earlier missing-parameter diagnosis based on shortened accessibility address text was corrected. Final device OAuth acceptance remains pending.
- 2026-10-18: Restored configured Android debug builds on Windows using a physical Gradle cache on E:; documented the linked-cache Kotlin DSL failure. Added explicit local Java/cache/build-configuration options to the verification script. Configured app installed and visually checked on the Android emulator; live sign-in and Huawei acceptance remain pending.

### Added
- 2026-10-19: Development admin-material schema/RPCs deployed as 20261019154009; protected assignment/link payloads separated from safe descriptors, revision checks, actor-scoped idempotency and recoverable lifecycle. All 163 material and 267 existing database assertions passed (430 total), fixtures rolled back; backend CI now includes the material suite. Student delivery and material editor UI remain unfinished.
- 2026-10-19: Administrator course-cover picker/private preview accepted on Huawei with persisted readback after restart, fresh-object replacement, removal and real Storage cleanup (2 test objects cleaned, 0 failed). Temporary course returned to recoverable deletion; student/iOS/release checks remain open. Admin material models/repository added with 80 focused tests; all 285 app tests and analysis pass, but material schema/UI are not yet deployed/integrated.
- 2026-10-19: Owner-approved SEA student-experience specification and phased acceptance criteria informed by signed-in competitor review: catalog discovery/access states, course/session library separation, safe resume and support. Planning only, not a claim of implemented student features; existing SEA privacy, payment and content rules retained.
- 2026-10-19: Physical Huawei administrator create/edit and recoverable course/session delete/restore accepted using an owner-approved temporary draft. Cancellation preserved the session; restoration returned draft; hosted readback verified exact EGP values and lifecycle audit events without publication. Final temporary course is soft-deleted/recoverable. Student visibility and release-signed acceptance remain separate gates.
- 2026-10-19: Private course-cover reservations/storage rules, guarded attachment and irreversible retirement/tombstone cleanup deployed to development. Client image normalization/authenticated storage service added without new dependencies or picker UI. 171 app tests, 267 database assertions and Android build passed; real binary upload, UI and physical acceptance remain pending.
- 2026-10-18: Recoverable course/session delete and restore controls with confirmation, server-returned state verification and mandatory draft restoration. Added lifecycle regression coverage; all 146 app tests passed. Fixed confirmation background-animation and narrow pagination-layout issues found by tests. Physical acceptance remains pending.
- 2026-10-18: Mobile administrator course/session list and create/edit screens, ordered 20-row pagination, exact decimal EGP input and draft/published/archived edits. Added 26 content-focused tests and 2 admin-entrypoint tests; all 117 Flutter tests passed. Physical editor acceptance and cover uploads remain pending.
- 2026-10-18: Course/session metadata foundation with integer-piaster EGP prices, explicit lifecycle/order fields, server-controlled identities, active-session/admin RLS and atomic audit events. Deployed development migration 20261018154932; 130 content checks and 84 identity checks passed with rollback fixture cleanup. Mobile editor verification is in progress; private cover/media uploads remain pending.
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
