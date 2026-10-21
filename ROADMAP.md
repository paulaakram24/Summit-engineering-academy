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
- [ ] 1.4 Server-authorized admin provisioning and physical device/session acceptance. Students require blocking new login until the current session logs out, not session replacement. Owner clarification 2026-10-20 exempts enabled server-authorized admins from device count and simultaneous-session limits.
  - [x] 1.4.1 Implement server-controlled roles, two registered installations, one active application session, and revoked/ended-session denial.
  - [x] 1.4.2 Bootstrap owner-selected first administrator bolaakram123@gmail.com through existing guarded provisioning SQL. Main confirmed verified, nonanonymous, nonbanned/enabled identity; readback on 2026-10-18: role admin, disabled=false, one device, one active session and one admin_provisioned audit event.
  - [x] 1.4.3 Confirm Administrator account and saved profile on physical Huawei after force-stop/restart (same evidence as 1.3.5).
  - [ ] 1.4.4 With an owner-controlled acceptance step, verify physical logout clears local access and ends the server session; restart remains signed out, then fresh login works. Do not log out the real owner merely to advance this checklist.
  - [ ] 1.4.5 Verify student second-installation login is blocked while the first session is active; after owner-approved logout, verify second-installation admission and the two-device cap. SQL fixture coverage is separate evidence. Admin accounts must instead admit simultaneous installations without ending older sessions.
  - [ ] 1.4.6 Administrator unlimited device/session exception and native acceptance.
    - [x] 1.4.6.1 Deploy current-role-based admin exemption, own-device context, independent logout and fail-closed demotion; migration 20261020102940. Atomic rollback preflight and fresh postdeployment verification each passed 631 database assertions, including 46 new admin/session checks; 466 app tests and analysis/formatting passed. Student limits preserved, owner admission untouched. See docs/ADMIN_SESSION_POLICY.md.
    - [x] 1.4.6.2 Owner-controlled emulator Google retry reaches Administrator home, confirmed by owner on 2026-10-20 after deployment; no Huawei logout/manual admission reset performed. This is reported interactive acceptance, not a fresh screenshot/readback.
    - [ ] 1.4.6.3 Verify independent restart/session persistence and per-session logout across installations; SQL peer-preservation tests do not substitute for native acceptance.
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
  - [x] 2.3.3 Integrate admin material lists/forms and recoverable lifecycle controls; local and controlled Huawei administrator flows accepted 2026-10-19. Media kinds remain nonpublishable placeholders until validated assets exist.
    - [x] 2.3.3.1 Administrator-only session Materials entry, paginated list/include-deleted, typed draft creation/editing and confirmed recoverable delete/restore integrated. Identity-bound operations, refetch-after-mutation and conservative refresh-only uncertain recovery retained; no media upload/delivery enabled.
    - [x] 2.3.3.2 Main verified all 355 app tests, clean analysis, locked dependencies, formatting (40 files, zero changes) and configured Android build (8.4s). Includes 38 panel tests, 5 entrypoint tests and 107 material model/repository checks. Focused independent final review found no unresolved concrete issue; not a full security audit. Physical acceptance remains below.
    - [x] 2.3.3.3 Final 355-test APK installed on Huawei: draft assignment create/private-detail edit, delete cancellation, delete/include-deleted/restore-to-draft passed; private HTTPS link and video placeholder saved and reopened after force-stop/restart. Hosted readback confirmed assignment revision 4, exact synthetic payloads, three draft creates and no publication. Temporary parent soft-deleted again; three draft materials remain recoverable beneath it. See docs/ADMIN_MATERIAL_EDITOR.md and docs/PHASE2_DEVICE_ACCEPTANCE.md. Student delivery and media bytes remain separate gates.
  - [ ] 2.3.4 Add private media upload/readiness, student-safe metadata projection and entitlement-checked delivery in coordination with Phases 3/4. Admin metadata alone is not playable content.
- [ ] 2.4 Catalog, search, filters, locked descriptions and free previews.
  - [x] 2.4.0 Adopt useful competitor patterns as SEA-specific acceptance requirements (owner authorized 2026-10-19); see docs/STUDENT_EXPERIENCE.md. This is a requirements checkpoint, not implemented catalog acceptance.
  - [ ] 2.4.1 Read-only published course cards/details with safe metadata, instructor/category/level and authoritative EGP prices; accessible fallback covers and distinct loading/error/empty states.
    - [x] 2.4.1.1 Reviewed read-only invoker catalog migration deployed to development as 20261019193939; 155 catalog assertions plus 430 existing regressions passed (585 total), with fixture cleanup zero. No private material grants changed; this was postdeployment verification, not atomic local preflight.
    - [x] 2.4.1.2 Typed actor-bound catalog client, strict projections, sanitized failures and cursor validation accepted with 77 focused model/transport tests. Same-actor token refresh is supported; account changes discard replies.
    - [x] 2.4.1.3 Browse courses entry, cards/details/outline and authenticated cover read/fallback integrated. Main passed 453 app tests (including 21 screen tests), clean analysis/47-file formatting and configured Android build (53.9s). Installed on Huawei: owner session retained, honest empty catalog, no-match search/clear and background access closure accepted without publication. Populated/native student/cover and release gates remain in 2.4.4; Phase 2 is not complete.
    - [x] 2.4.1.4 Confirmed-withdrawal return flow corrected: unavailable detail invalidates cached cards/cursor and requires fresh search. Thirteen additional regressions cover this case, filter-option removal, query cursor reset, hardware Back, dependency replacement, delayed detail/outline results, outline pagination/duplicates and real PNG rendering/clearing in widgets. Main passed all 466 app tests, clean analysis/49-file formatting and Android rebuild (9.2s); newest local APK not yet installed because phone remains at 2%. No positive native image or populated acceptance inferred.
  - [ ] 2.4.2 Server-side catalog search and category/level filters before stable pagination; clear filters, preserve return state and reject stale query/account responses. Do not search only a loaded page.
    - [x] 2.4.2.1 Literal server substring search and full-catalog filter options precede keyset pagination; backend later-page/combined-filter/wildcard tests and client stale-page/cursor/duplicate/account tests passed. Query and later-card scroll position survive details/back in widget tests. Populated physical search/filter acceptance remains open.
  - [ ] 2.4.3 Text/icon access labels for free preview, locked, pending, available and unavailable, integrated with server policy. Draft/deleted content stays hidden; no invented coming-soon publication state.
  - [ ] 2.4.4 Verify student visibility, denied protected payloads, combined filters, later-page matches, screen readers and small-screen/large-text layouts on real devices.
    - [x] 2.4.4.1 Owner approved temporary clearly labeled synthetic course/session publication, populated-screen checks and final archiving (2026-10-20), without payments or real learning materials. This is authorization, not runtime acceptance or push approval; do not request it again.
    - [x] 2.4.4.2 Complete bounded populated workflow on owner-authorized Android Studio emulator/admin account (2026-10-20): drafts hidden, course with unpublished session empty, published session/price/preview designation, combined instructor/category/level search, detail-return criteria, background closure/fresh reopen, archive both new synthetic entities and confirm no published test content remains. Normal admitted admin UI only; older deleted course untouched. See docs/PHASE2_DEVICE_ACCEPTANCE.md. This does not close student or real-device gates.
    - [x] 2.4.4.3 Android Studio's existing Medium_Phone_API_37.0 emulator booted online (Android 17/API 37); latest 466-test APK installed and device hash matched local 7884B004…981FF6. Signed-out SEA/Google button visually confirmed. No AVD wipe, owner login automation, new account privileges or authenticated/populated acceptance claimed.
    - [ ] 2.4.4.4 Remaining native acceptance: actual student account visibility/denials, positive authenticated Storage cover rendering, later-page matches, screen-reader and small-screen/large-text layouts, plus Huawei and signed-release verification. SQL/widget coverage remains separate evidence.
    - [x] 2.4.4.5 Automated accessibility follow-up: 21 new tests cover 320/360x640 at 2x/3x text, long cards/outline/filter labels, actual popup wrapping, compact selected-label bounds/full semantics/long-press tooltip, retry/error/empty states, labeled/Android/iOS touch-target guidelines and four asynchronous live-region results. Main passed all 487 app tests, analysis/50-file formatting and Android rebuild (18.3s). Native 320-width/2x-font catalog-control probe only; original display settings restored. Actual TalkBack/student/physical-device/release gates remain open. See docs/CATALOG_ACCESSIBILITY.md. This follow-up is unpushed.
    - [x] 2.4.4.6 Latest FF6BC235…03FEEA APK: owner fresh Google login/admin home, force-stop/relaunch identity restoration and positive private cover rendering in catalog/detail accepted on emulator. Read-only Storage metadata confirms attached 29842-byte PNG/private bucket. Owner confirmed republishing/cover changes and approved final archive; session then course archived normally, cover plus one material row preserved, zero published courses and final empty catalog verified. Student/anonymous denial, actual TalkBack/Huawei/iOS/release remain open. See docs/PHASE2_DEVICE_ACCEPTANCE.md.
- [ ] 2.5 My Courses, purchased sessions and bookmarks.
  - [ ] 2.5.1 Separate full-course ownership and individual-session purchases, with All learning/Full courses/Individual sessions views and accurate empty states. Individual-session purchase must not imply course enrollment.
  - [ ] 2.5.2 Integrate real Phase 3 entitlements/payment states, recent/alphabetical sorting and account-change clearing; no fake ownership, duplicate cards or protected access for pending/rejected requests.
  - [ ] 2.5.3 Course bookmarks as a separate Saved courses slice, never purchases/enrollment.
    - [x] 2.5.3.1 Prepare bounded integration/security/verification design with Agency Agents Mobile App Builder (docs/SAVED_COURSES_DESIGN.md, 2026-10-20). Design only; persistence/API/UI and final retention contract are not implemented.
    - [x] 2.5.3.2 Implement owner-scoped persistence, availability-filtered pagination and actor-bound transport with revision compare-and-set. Migration 20261020132830 deployed; 715 hosted assertions passed both preflight and postdeployment (84 new), 561 app tests passed (74 new). Anonymous HTTP denied; fixtures rolled back. Supabase guidance informed least privilege/RLS and row serialization. No real parallel-race or native persistence claim.
    - [ ] 2.5.3.3 Complete accessible save/remove/list acceptance, hidden-reference management and native checks.
      - [x] 2.5.3.3.1 UI integrated through catalog saved-only mode and authenticated Saved courses entry; automated transport/widget/account/lifecycle/accessibility checks passed. Backend verified before runtime activation; no fake ownership or local-only persistence.
      - [x] 2.5.3.3.2 Metadata-free bulk management implemented: confirmed Remove unavailable saved courses updates only own unavailable saved=true references, retains false tombstones and advances revisions atomically. Migration 20261021001423 deployed; all 744 backend assertions and 585 app tests passed. No hidden metadata or purchase/access changes. Sequential stale-write/overflow rollback tests passed; real parallel-race evidence remains separate.
      - [ ] 2.5.3.3.3 Verify populated save/remove/restart and native student/TalkBack/Huawei/release behavior; record actual artifact and bounded outcomes separately.
      - [x] 2.5.3.3.4 Bounded emulator/admin acceptance: final 8EC6FFE7…A04A2F APK installed and device hash matched, existing Administrator home retained, Saved courses honest empty state/disclaimer rendered, background closure cleared the old route. Final build 40.8s, 561 tests, clean analysis/55-file formatting. No published course/save mutation or populated persistence claim.
      - [x] 2.5.3.3.5 Cleanup artifact 9F59BB0B…D5E4890 installed/hash-matched on emulator; native dialog/cancel/confirmed zero-row result and refreshed list accepted. Hosted total bookmark rows zero before/after: no real saved references removed. 585 tests/56-file formatting/build 15.5s; populated/student/TalkBack/Huawei/release gates remain open.
Exit: admin publishes content; students see only allowed metadata and previews.

## 3. Commerce and entitlements
- [ ] 3.1 Confirm expiry rule, bundle behavior and distribution/payment policy.
  - [x] 3.1.1 Owner confirmed access starts on admin approval with no automatic expiry, subject to continued session availability (2026-10-19).
  - [ ] 3.1.2 Finish commerce transition details and store-distribution/payment policy; preserve purchase history through removal/restoration.
    - [x] 3.1.2.1 Owner clarified editable admin/instructor-selected session bundles at one EGP price (2026-10-20): membership additions/removals apply to both existing buyers and new buyers; future sessions excluded until selected. Preserve purchase snapshots and audit revisions; current coverage follows membership without bypassing restoration gates or revoking independent grants. Admins currently perform instructor duties; no new role.
    - [x] 3.1.2.2 Owner confirmed case-by-case full/partial refunds and a separately recorded explicit retain/revoke access decision (2026-10-20). Actual funds returned manually outside SEA via InstaPay/Vodafone Cash; no automatic transfer or amount-based access change. Operational reconciliation/overlapping revocation scope remain open.
    - [x] 3.1.2.3 Owner rejected automatic restoration when archived content is republished (2026-10-20): require a fresh explicit admin grant, preserve history and do not infer a second payment. Existing course/bundle coverage must not bypass this restoration gate.
    - [ ] 3.1.2.4 Resolve remaining transition rules (including operational refund reconciliation, overlapping grant revocations and approvals of unavailable content) before enabling affected operations; complete current store-distribution/payment policy review before release. Bundle membership edit impact and basic refund discretion/partial/explicit-access policy are resolved in 3.1.2.1–2, not open owner decisions.
    - [x] 3.1.2.5 Initial official Apple/Google billing-policy review recorded in docs/DISTRIBUTION_PAYMENT_REVIEW.md (2026-10-20). Digital-content billing rules mean manual verification is not proof of store eligibility. Owner asked to choose initial distribution/billing direction; no exemption, final policy clearance or release readiness claimed.
    - [x] 3.1.2.6 Owner selected direct Android installation initially (2026-10-20), retaining mobile Student/Admin manual InstaPay/Vodafone Cash method selection, screenshot upload and actual-funds admin verification. Public-store/iPhone distribution deferred. This resolves initial channel choice only; remaining commerce transitions and production release gates stay open. Revalidate store billing/eligibility before any later store launch.
  - [x] 3.1.3 Prepare proposed entitlement/access-state contract and denial matrix in docs/ENTITLEMENTS_DESIGN.md (Backend Architect, 2026-10-20). Documentation only; no orders/grants, payment acceptance, status projection or protected delivery implemented. Business decisions in 3.1.2 remain open.
- [ ] 3.2 Ask user for InstaPay/Vodafone Cash destination details at this milestone.
- [ ] 3.3 Orders, server-set prices, private receipt submission and pending states.
  - [x] 3.3.1 Private course/session pending-intent foundation deployed to development as 20261021002402; immutable server snapshots, own-history pagination and operation idempotency checked by 70 new assertions (814 backend total), strict Dart models by 32 new tests (617 app total). Creation execution remains closed at both entry points, including service_role; no real orders or payment/access actions created. No bundle or parallel-transaction acceptance inferred.
    - [x] 3.3.1.1 Actor-pinned read-only history transport verified: 35 new tests, 652 app total, clean analysis/61-file formatting and configured debug build (3.1s). Pinned JWT, account-switch rejection, safe errors and request-bound entity/cursor validation; no creation method, runtime injection or checkout UI. Independent bounded review found no concrete blocker.
  - [ ] 3.3.2 Resolve repeat/overlap, changed-price/unavailable-at-approval and admin-purchase rules before enabling creation/checkout; collect destinations at 3.2, implement method selection/private evidence separately and add editable bundle integration.
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
- [ ] 8.1 Ownership, stable production identifiers and Android release signing credentials/secure backup; developer-store accounts deferred until later store distribution.
- [ ] 8.2 Before later store distribution, validate digital-course billing rules in target storefronts. Initial direct-Android channel is selected; this checkbox is a deferred store gate, not a requirement to replace the chosen manual payment flow now.
- [ ] 8.3 Privacy disclosures, account deletion, support details and store assets.
- [ ] 8.4 Signed Android release-candidate build and internal acceptance, separate from the debug APK.
  - [ ] 8.4.1 Verify stable identifier/signing identity, protected key backup and update compatibility.
  - [ ] 8.4.2 Configure and verify trustworthy HTTPS APK download, artifact integrity, version/update/support instructions and recovery procedures; no hosting provider selected yet.
  - [ ] 8.4.3 Verify production API configuration and payment/access/revocation flows on the signed artifact before owner-approved direct distribution.
- [ ] 8.5 Deferred iPhone release: macOS runner/Mac access, iOS build and TestFlight testing; no equivalent public iPhone sideloading path assumed.
- [ ] 8.6 Production configuration, monitoring, backup and rollback checks.
- [ ] 8.7 Explicit user release approval and direct Android distribution; separate later approval/policy review required for store submission.
Exit: approved releases, production smoke tests and support handoff completed.

## Execution rules
Parallelize disjoint UI, backend, documentation and review tasks. Integrate after each tested milestone. Keep live-account setup pending when credentials are absent; continue local tests. Update PROJECT_STATUS.md with evidence, blockers and the next milestone each work session. ROADMAP.md phases 0–8 are the canonical delivery numbering. Preserve sources/ as read-only. Never request passwords in chat. Each follow-up push requires fresh explicit user approval; earlier checkpoint approval does not authorize new changes.

Next: settle docs/MORNING_QUESTIONS.md before enabling actual orders/checkout, then collect public payment destinations at 3.2 and implement the approved transitions and bundle integration. Safe private foundation and read-only transport are verified, not runtime-integrated checkout. Saved courses and unavailable-reference cleanup are implemented; populated/student/TalkBack/Huawei/release checks remain open. Current verified local checkpoint: 652 app tests, 814 hosted backend assertions and Android debug build; latest pushed milestone b97aba4 has both GitHub workflows passed. These counts do not prove payments, entitlements or protected learning. Administrator material UI (2.3.3) and cover acceptance (2.1.4.4) are complete, not Phase 2 as a whole. Integrate 2.4.3 access labels/2.5 library only with real Phase 3 grants. Keep 2.3.4 uploads/delivery and deferred Phase 1 gates open. Initial release is direct Android with manual payments; production signing/distribution remains Phase 8. All post-push work requires fresh approval before another push.
