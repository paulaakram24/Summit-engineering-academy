# Implementation roadmap

Each milestone proceeds through implementation, verification, and status recording. A milestone is complete only when its exit check passes. External account dependencies must not stop independent local development. No production readiness claim until live integrations and device tests pass.

## 0. Foundation — locally verified, pushed and remote CI passed
- [x] 0.1 Inspect repository and preserve existing documents/assets.
- [x] 0.2 Verify Flutter/Dart, Android SDK, Java and CLI tools; physical Huawei Android 9 substitutes for the failing emulator.
- [x] 0.3 Reconcile original requirements with generated planning documents (see REQUIREMENTS_CORRECTIONS.md for open decisions).
- [x] 0.4 Create Android/iOS Flutter shell, branding/theme, lint and test setup (foundation analysis/widget tests and Android build passed; iOS runtime remains a release gate).
- [x] 0.5 Establish automated checks and development configuration (local checks and GitHub-hosted run 38745284449 passed).
Exit: shell analyzes cleanly, widget test passes, Android build succeeds.

## 1. Identity and backend — core Google/admin identity accepted; remaining live gates open
- [x] 1.1 Create development Supabase project; record configuration without secrets (summit-academy-dev verified ACTIVE_HEALTHY in Frankfurt).
- [x] 1.2 Design migrations, ownership, roles, RLS and private storage (deployed to dev; initial 78 database assertions passed).
- [ ] 1.3 Registration, email verification, login, reset, Google sign-in and profile; complete only after remaining live checks pass.
  - [x] 1.3.1 Implement registration/login, verification and password-reset screens, secure session/PKCE persistence, and callback handling; automated coverage exists. Live email delivery is a separate gate.
  - [x] 1.3.2 Implement fresh SDK-generated Google OAuth with capability-checked isolated Chrome Custom Tabs and browser fallback; preserve session security policy.
  - [x] 1.3.3 Require reviewed/saved name, phone and university before entry, with shared form/controller validation; complete returning profiles do not repeat completion.
  - [x] 1.3.4 Accept fresh Google sign-in, callback and required profile save on physical Huawei ANE-LX1 (Android 9), confirmed by owner and personalized welcome screen on 2026-10-18.
  - [x] 1.3.5 Verify signed-in session/profile persistence after physical Huawei force-stop/restart on 2026-10-18; Administrator account restored. Local evidence: E:/Android-prerequisites-Summit/sea-admin-restart-check.png. Initial activity wait timed out; this is not a cold-start performance benchmark.
  - [ ] 1.3.6 Verify live email registration, confirmation delivery/link return and subsequent email/password login.
  - [ ] 1.3.7 Verify live password-reset delivery, recovery link, password update and required fresh login.
  - [ ] 1.3.8 Complete physical OAuth cancellation and cold/warm callback failure checks, including expired/replayed callbacks; automated tests alone do not close these live gates.
- [ ] 1.4 Server-authorized admin provisioning and physical device/session acceptance. Owner requires blocking new login until the current session logs out, not session replacement.
  - [x] 1.4.1 Implement server-controlled roles, two registered installations, one active application session, and revoked/ended-session denial.
  - [x] 1.4.2 Bootstrap owner-selected first administrator bolaakram123@gmail.com through existing guarded provisioning SQL. Main confirmed verified, nonanonymous, nonbanned/enabled identity; readback on 2026-10-18: role admin, disabled=false, one device, one active session and one admin_provisioned audit event.
  - [x] 1.4.3 Confirm Administrator account and saved profile on physical Huawei after force-stop/restart (same evidence as 1.3.5).
  - [ ] 1.4.4 With an owner-controlled acceptance step, verify physical logout clears local access and ends the server session; restart remains signed out, then fresh login works. Do not log out the real owner merely to advance this checklist.
  - [ ] 1.4.5 Verify physical second-installation login is blocked while the first session is active; after owner-approved logout, verify second-installation admission and the two-device cap. SQL fixture coverage is separate evidence.
- [x] 1.5 Automated identity authorization regression verified within the scope below; this does not close 1.3/1.4 live acceptance or certify production readiness.
  - [x] 1.5.1 Main parsed a fresh hosted-dev PASS 84/84 on 2026-10-18 for cross-user denial, role escalation, private storage, device/session restrictions, revoked/expired/ended sessions and logout-before-registration regression. Suite uses rollback-based fictional fixtures; it does not exercise live email or physical-device flows.
  - [x] 1.5.2 Historical hosted Flutter CI 39117499042 and backend CI 39117499090 passed for pushed checkpoint 975bf67; this is not CI evidence for subsequent unpushed changes.
  - [x] 1.5.3 Current local verification: all 89 Flutter tests, static analysis and configured Android debug APK build passed; physical Google/profile and administrator restart acceptance are recorded separately above.

Verification follow-ups:
- [x] Confirm reserved-fixture cleanup after the fresh 2026-10-18 hosted suite: zero reserved fixture users; owner's complete profile, enabled administrator and single active session preserved.
- [ ] Extend concurrency evidence beyond the previously observed parallel admission result: commit/rollback serialization, device-cap races and logout/register ordering remain unverified (see docs/PHASE1_DATABASE_TESTS.md).
Exit: student/admin authentication works and unauthorized access fails in integration tests.

## 2. Content and discovery
- [ ] 2.0 Define content contracts, role/RLS and private-upload access rules, and the first admin content workflow before implementing 2.1. Core Google/admin identity and restart acceptance permit this work to start while Phase 1 email, recovery, logout and new-device gates remain explicitly open. Specify course/session fields, ordering, EGP prices, cover ownership and draft/published/archived visibility; retain denial tests as an implementation requirement. No content feature is complete yet.
- [ ] 2.1 Admin course/session editor, ordering, prices and cover uploads.
- [ ] 2.2 Draft/published/archived lifecycle and soft-delete/restore.
- [ ] 2.3 Multiple videos, PDFs, attachments, assignments and links per session.
- [ ] 2.4 Catalog, search, filters, locked descriptions and free previews.
- [ ] 2.5 My Courses, purchased sessions and bookmarks.
Exit: admin publishes content; students see only allowed metadata and previews.

## 3. Commerce and entitlements
- [ ] 3.1 Confirm expiry rule, bundle behavior and distribution/payment policy.
- [ ] 3.2 Ask user for InstaPay/Vodafone Cash destination details at this milestone.
- [ ] 3.3 Orders, server-set prices, private receipt submission and pending states.
- [ ] 3.4 Admin verification against actual payment records; approve/reject with audit trail.
- [ ] 3.5 Atomic/idempotent grants, course future-session access, bundles, cash/manual grants.
- [ ] 3.6 Expiry, revocation and duplicate-payment tests.
Exit: payment approval unlocks exactly the purchased content once; rejection grants nothing.

## 4. Protected learning
- [ ] 4.1 Cloudflare Stream upload/processing and signed playback integration.
- [ ] 4.2 Server entitlement/device/session checks before issuing short-lived access.
- [ ] 4.3 Playback resume, 90% completion and manual completion.
- [ ] 4.4 View-only PDFs, permitted file downloads and identity watermark.
- [ ] 4.5 Test expiry/revocation, backgrounding, interrupted networks and real devices.
Exit: complete purchase-to-learning flow passes, including denied/expired access.

## 5. Student interaction
- [ ] 5.1 Assignment submission and assignment grades/feedback.
- [ ] 5.2 Private student/admin messaging.
- [ ] 5.3 In-app notifications and delivery queue.
- [ ] 5.4 Gmail SMTP, push and existing WhatsApp provider integration with consent/retries.
- [ ] 5.5 Light/dark themes, accessibility and empty/error/loading states.
Exit: assignment, messaging and configured notification channels work end to end.

## 6. Operations
- [ ] 6.1 Student/access/device administration and recovery workflows.
- [ ] 6.2 Revenue, sales, registrations and learning analytics.
- [ ] 6.3 CSV/Excel exports with access controls.
- [ ] 6.4 Audit log viewer, backup/restore rehearsal and operational documentation.
Exit: administrators can operate and recover the service using documented procedures.

## 7. Independent verification
- [ ] 7.1 Agent review of feature completeness and failure cases.
- [ ] 7.2 Security review of RLS, uploads, payments, tokens and device enforcement.
- [ ] 7.3 Claude Code audit handoff; run when available and record actual results.
- [ ] 7.4 Regression, accessibility, performance and real-device acceptance testing.
- [ ] 7.5 Resolve findings and record remaining limitations.
Exit: critical findings resolved and release candidate acceptance evidence recorded.

## 8. Release
- [ ] 8.1 Developer accounts, ownership, identifiers and signing credentials.
- [ ] 8.2 Validate store billing rules for digital courses in target storefronts before shipping purchase UI.
- [ ] 8.3 Privacy disclosures, account deletion, support details and store assets.
- [ ] 8.4 Signed Android internal-test build and acceptance.
- [ ] 8.5 macOS runner/Mac access, iOS build and TestFlight testing.
- [ ] 8.6 Production configuration, monitoring, backup and rollback checks.
- [ ] 8.7 User release approval and store submission.
Exit: approved releases, production smoke tests and support handoff completed.

## Execution rules
Parallelize disjoint UI, backend, documentation and review tasks. Integrate after each tested milestone. Keep live-account setup pending when credentials are absent; continue local tests. Update PROJECT_STATUS.md with evidence, blockers and the next milestone each work session. ROADMAP.md phases 0–8 are the canonical delivery numbering. Preserve sources/ as read-only. Never request passwords in chat. Each follow-up push requires fresh explicit user approval; earlier checkpoint approval does not authorize new changes.

Next implementation: 2.0 content contracts/RLS and then 2.1 admin course/session editor, following the accepted Google/profile, first-admin bootstrap and physical restart checks. Keep Phase 1 open until its remaining email/reset, logout and new-device acceptance gates pass. Hosted-fixture cleanup was verified. Owner approved this milestone's push on 2026-10-18 after verification; subsequent changes require fresh approval.
