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
    - Deferred by owner on 2026-10-19 while academy Google account recovery is on a 72-hour hold. A separate 72-hour reminder is active; 1.3.6/1.3.7 remain release gates, and independent content work continues.
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
- [x] 2.0 Define content contracts, role/RLS and private-upload boundaries before implementing 2.1 (docs/CONTENT_CONTRACT.md, 2026-10-18). Prices use integer piasters; metadata excludes protected materials; covers follow the separate reservation/private-storage contract in 2.1.4. Contract completion is not runtime feature acceptance.
- [ ] 2.1 Admin course/session editor, ordering, prices and cover uploads.
  - [x] 2.1.1 Deploy course/session metadata schema, active-admin RLS, explicit write-column grants and atomic audit events (20261018154932_phase2_content_core). Hosted content suite passed 130/130; identity regression passed 84/84; reserved fixtures absent afterward.
  - [x] 2.1.2 Implement paginated course/session lists and create/edit forms with exact EGP validation and draft/published/archived controls; full Flutter suite passed 117/117 with clean analysis. This is automated acceptance; physical/API user-flow acceptance stays in 2.1.3.
  - [ ] 2.1.3 Build/install on Huawei and accept live admin create/edit and student denial. No live content acceptance claimed from SQL fixtures alone.
    - [x] 2.1.3.1 Latest APK installed; restored admin access, live empty catalog, new-course form and required-field validation visually checked on Huawei (2026-10-19). No content saved.
    - [x] 2.1.3.2 Owner-approved temporary draft course/session created, edited, deleted/restored on Huawei; exact prices confirmed by hosted readback (2026-10-19). Final course soft-deleted/recoverable, never published. See docs/PHASE2_DEVICE_ACCEPTANCE.md.
    - [ ] 2.1.3.3 Physical student denial and signed release-artifact acceptance remain separate gates; administrator debug-build testing does not close them.
  - [ ] 2.1.4 Implement validated private cover uploads, controlled reads and orphan cleanup.
    - [x] 2.1.4.1 Backend reservations, immutable objects, active-admin upload/attachment, published-cover reads and safe retired-object cleanup; migration 20261019015308 deployed, 53 cover + 84 identity + 130 content assertions passed with fixture cleanup confirmed. No exhaustive concurrency/binary-upload claim.
    - [x] 2.1.4.2 Client image size/dimension/type validation, metadata-stripping PNG normalization and authenticated storage service with bounded cleanup; initial service checkpoint passed 171 app tests and Android build. Picker/preview integration follows in 2.1.4.3.
    - [x] 2.1.4.3 Integrate system image selection, private preview, confirmed replacement/removal and explicit bounded cleanup UI; no arbitrary URL or public-bucket shortcut. Initial integrated checkpoint passed 205 tests and Android build; physical acceptance recorded below.
    - [x] 2.1.4.4 Real Storage upload/readback, private preview after app restart, fresh-object replacement, removal and explicit cleanup accepted on Huawei (2026-10-19). Two normalized 330203-byte PNGs retired/cleaned; zero corresponding Storage objects remain. Picker cancellation accepted earlier. Temporary course returned to recoverable archived/deleted state, never published. See docs/PHASE2_DEVICE_ACCEPTANCE.md; student/iOS/release and concurrency gates are separate.
- [ ] 2.2 Draft/published/archived lifecycle and soft-delete/restore.
  - [x] 2.2.1 Backend soft deletion archives content; restoration forces draft; deleted parents hide sessions and deny edits (covered by the hosted 130-check suite).
  - [x] 2.2.2 Mobile confirmation, delete/restore controls and Include deleted workflow implemented; lifecycle repository/UI regression included in 146 passing app tests. No permanent deletion exposed.
  - [ ] 2.2.3 Physical-device delete/restore acceptance, confirming student visibility and explicit republication after restoration.
    - [x] 2.2.3.1 Administrator Huawei course/session deletion and restore-to-draft accepted with owner-authorized temporary content; cancellation preserves session and deleted-parent edit/session controls are disabled.
    - [ ] 2.2.3.2 Student-side visibility and explicit republication acceptance remain open. Temporary acceptance content must not be published merely to complete this checklist.
- [ ] 2.3 Multiple videos, PDFs, attachments, assignments and links per session.
  - [x] 2.3.1 Admin-only metadata/protected payload schema and idempotent revision-checked mutations deployed to development (20261019154009). Main parsed 163/163 material assertions; identity/content/covers regressions also passed (430 total), with fixture cleanup confirmed. No student media delivery or concurrency acceptance implied.
  - [x] 2.3.2 Typed admin material models/repository with strict projection, actor-bound stable operation UUIDs, stale-revision handling and mandatory refetch after mutation. Main verified all 310 app tests, clean analysis, formatting and configured Android build (4.1s) after the actor-switch correction; focused client coverage totals 105 tests. Independent focused reinspection found no remaining concrete actor-binding/token-pinning regression. UI remains unintegrated; this is not full security or physical material acceptance.
  - [ ] 2.3.3 Integrate admin material lists/forms and recoverable lifecycle controls; verify real user flows after backend acceptance. Media kinds remain nonpublishable placeholders until validated assets exist.
  - [ ] 2.3.4 Add private media upload/readiness, student-safe metadata projection and entitlement-checked delivery in coordination with Phases 3/4. Admin metadata alone is not playable content.
- [ ] 2.4 Catalog, search, filters, locked descriptions and free previews.
  - [x] 2.4.0 Adopt useful competitor patterns as SEA-specific acceptance requirements (owner authorized 2026-10-19); see docs/STUDENT_EXPERIENCE.md. This is a requirements checkpoint, not implemented catalog acceptance.
  - [ ] 2.4.1 Read-only published course cards/details with safe metadata, instructor/category/level and authoritative EGP prices; accessible fallback covers and distinct loading/error/empty states.
  - [ ] 2.4.2 Server-side catalog search and category/level filters before stable pagination; clear filters, preserve return state and reject stale query/account responses. Do not search only a loaded page.
  - [ ] 2.4.3 Text/icon access labels for free preview, locked, pending, available and unavailable, integrated with server policy. Draft/deleted content stays hidden; no invented coming-soon publication state.
  - [ ] 2.4.4 Verify student visibility, denied protected payloads, combined filters, later-page matches, screen readers and small-screen/large-text layouts on real devices.
- [ ] 2.5 My Courses, purchased sessions and bookmarks.
  - [ ] 2.5.1 Separate full-course ownership and individual-session purchases, with All learning/Full courses/Individual sessions views and accurate empty states. Individual-session purchase must not imply course enrollment.
  - [ ] 2.5.2 Integrate real Phase 3 entitlements/payment states, recent/alphabetical sorting and account-change clearing; no fake ownership, duplicate cards or protected access for pending/rejected requests.
Exit: admin publishes content; students see only allowed metadata and previews.

## 3. Commerce and entitlements
- [ ] 3.1 Confirm expiry rule, bundle behavior and distribution/payment policy.
  - [x] 3.1.1 Owner confirmed access starts on admin approval with no automatic expiry, subject to continued session availability (2026-10-19).
  - [ ] 3.1.2 Bundle/refund details and store-distribution/payment policy remain open; removal/restoration semantics must not be confused with deleting purchase history.
- [ ] 3.2 Ask user for InstaPay/Vodafone Cash destination details at this milestone.
- [ ] 3.3 Orders, server-set prices, private receipt submission and pending states.
- [ ] 3.4 Admin verification against actual payment records; approve/reject with audit trail.
- [ ] 3.5 Atomic/idempotent grants, course future-session access, bundles, cash/manual grants.
- [ ] 3.6 No-automatic-expiry, content removal/access revocation and duplicate-payment tests under the confirmed approval-start policy.
Exit: payment approval unlocks exactly the purchased content once; rejection grants nothing.

## 4. Protected learning
- [ ] 4.1 Cloudflare Stream upload/processing and signed playback integration.
- [ ] 4.2 Server entitlement/device/session checks before issuing short-lived access.
- [ ] 4.3 Playback resume, 90% completion and manual completion.
  - [ ] 4.3.1 Continue learning revalidates access and restores a persisted playback point; seek/open alone cannot imply watched completion. Course-completion counts remain hidden by default.
- [ ] 4.4 View-only PDFs, permitted file downloads and identity watermark.
- [ ] 4.5 Test expiry/revocation, backgrounding, interrupted networks and real devices.
Exit: complete purchase-to-learning flow passes, including denied/expired access.

## 5. Student interaction
- [ ] 5.1 Assignment submission and assignment grades/feedback.
- [ ] 5.2 Private student/admin messaging.
- [ ] 5.3 In-app notifications and delivery queue.
- [ ] 5.4 Gmail SMTP, push and existing WhatsApp provider integration with consent/retries.
- [ ] 5.5 Light/dark themes, accessibility and empty/error/loading states.
  - [ ] 5.5.1 Accessible Help entry using configured SEA contacts; no overlapping floating controls, fabricated claims or copied competitor policies. Follow docs/STUDENT_EXPERIENCE.md across discovery/library/player layouts.
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

Next implementation: 2.3.3 admin material lists/forms using the deployed admin-only schema and verified actor-bound repository. Cover administrator physical acceptance (2.1.4.4) is complete; student/iOS/release gates remain open. Follow with the owner-approved 2.4 discovery and 2.5 learning-library slices in docs/STUDENT_EXPERIENCE.md. Keep Phase 1 open for deferred email/reset, logout and new-device acceptance. All current follow-up changes require fresh approval before pushing; previous push approvals do not carry forward.
