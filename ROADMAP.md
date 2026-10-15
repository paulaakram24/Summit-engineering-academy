# Implementation roadmap

Each milestone proceeds through implementation, verification, and status recording. A milestone is complete only when its exit check passes. External account dependencies must not stop independent local development. No production readiness claim until live integrations and device tests pass.

## 0. Foundation — locally verified, awaiting push approval
- [x] 0.1 Inspect repository and preserve existing documents/assets.
- [x] 0.2 Verify Flutter/Dart, Android SDK, Java and CLI tools; physical Huawei Android 9 substitutes for the failing emulator.
- [x] 0.3 Reconcile original requirements with generated planning documents (see REQUIREMENTS_CORRECTIONS.md for open decisions).
- [x] 0.4 Create Android/iOS Flutter shell, branding/theme, lint and test setup (analysis and two widget tests pass; Android build remains the phase exit gate).
- [x] 0.5 Establish automated checks and development configuration (local checks pass; GitHub-hosted run awaits push approval).
Exit: shell analyzes cleanly, widget test passes, Android build succeeds.

## 1. Identity and backend
- [ ] 1.1 Create development Supabase project; record configuration without secrets.
- [ ] 1.2 Design migrations, ownership, roles, RLS and private storage.
- [ ] 1.3 Registration, email verification, login, reset, Google sign-in and profile.
- [ ] 1.4 Server-authorized admin provisioning, two-device registration and session replacement.
- [ ] 1.5 Test cross-user access denial, role escalation and revoked sessions.
Exit: student/admin authentication works and unauthorized access fails in integration tests.

## 2. Content and discovery
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
Parallelize disjoint UI, backend, documentation and review tasks. Integrate after each tested milestone. Keep live-account setup pending when credentials are absent; continue local tests. Update PROJECT_STATUS.md with evidence, blockers and the next milestone each work session. Preserve sources/ as read-only. Never request passwords in chat.
