# Master Codex Build Prompt — Summit Engineering Academy

Follow ROADMAP.md for phased execution and REQUIREMENTS_CORRECTIONS.md for reconciled requirements that override earlier omissions below.

You are the lead product engineer responsible for building Summit Engineering Academy, a production-quality mobile learning and commerce app. Inspect the existing repository before changing anything. Preserve working code, respect existing conventions, and never overwrite or delete useful work. Treat `sources/` as read-only reference material.

## Product scope

Build one English, colorful, student-focused Flutter + Dart app with role-based Student and Admin experiences. Students self-register with name, email, phone, password, university, and may use Google sign-in. Admins are also the instructors for now and manage courses and content.

Use the supplied official logo at `assets/sea-logo.png` as the primary brand asset. Preserve its SEA Academy artwork and navy/teal/gold palette. Use it consistently on the splash screen, authentication, dashboards, profile/admin surfaces, notifications where appropriate, and app-store icon preparation. Generate platform-specific crops/sizes only from this source asset; do not replace it with a newly invented logo.

The content hierarchy is Course → Sessions → multiple videos/files/links. Courses and sessions support Draft, Published, and Archived states. Sessions are released immediately when published. Students can see published course/session metadata, including locked items and free previews where configured.

Students can buy an individual session, an editable admin/instructor-selected session bundle or complete course using one-time EGP purchases. A course purchase covers existing and future sessions subject to server availability/restoration rules. Bundles have one EGP price; later sessions are excluded unless explicitly added. Bundle membership additions/removals apply to existing buyers and new buyers alike. Preserve immutable purchase snapshots and audit membership revisions while resolving current bundle coverage dynamically; do not rewrite purchase history. Bundle edits cannot bypass availability/restoration gates or revoke independent valid grants. Admins currently perform instructor duties; no separate Instructor role is introduced. Admins can manually enroll, grant/revoke access, and record cash purchases. Access starts on admin approval with no automatic business expiry. Archiving and republication do not erase history or automatically restore old purchased access: require a fresh audited admin grant for the affected content, not an assumed second payment. No subscriptions are required initially.

## Payments

Owner clarification 2026-10-21: reuse an existing unpaid request for the same target, block purchases already covered by valid access, honor recorded request prices, and reject content unavailable before approval (manually refund received funds, with separate return records). Source-only revocation applies when an explicit refund access decision is revoke; independent valid grants survive. Admins access all learning content through server-controlled administrative authorization, without purchases/approvals or fabricated student ownership. Retain admission, lifecycle/privacy and resource-readiness checks.

Payment receiving details are per assigned course instructor: a configured phone number receiving an InstaPay bank-account transfer and, optionally, Vodafone Cash at the same number. Each instructor chooses InstaPay only or both methods. Do not use a global academy receiver, infer financial identity from a free-text instructor name, invent receiving details or expose unconfigured methods. Resolve instructor account association, destination edit authority, recipient display details and cross-instructor bundle payee before enabling payment instructions.

Resolved follow-up: assign one authenticated instructor/Admin per course; sessions inherit it and instructors edit their own receiving profiles. Bundles must stay within that same course and use its instructor, not cross-course recipients or split transfers. Store only number, recipient name and method selection—no bank-name field. Changing receiving details or course receiver pauses existing unpaid requests for instructor review before new instructions; preserve destination history, recorded price and prior transfers. Implementation/tests are required; answers alone do not enable the staged order API.

Initial distribution is direct Android installation, selected by the owner on 2026-10-20. Defer Google Play/App Store submission and public iPhone release; revalidate their billing requirements before a later store build. Do not introduce store billing or a website without a new scope decision. Direct production distribution still requires a signed release artifact, secure key handling, verified download/update procedures and explicit release approval; never publish the debug APK as production.

Implement manual InstaPay and Vodafone Cash payment flows:

1. Student creates a pending order.
2. Student selects InstaPay or Vodafone Cash; app displays the corresponding configured payment instructions and server-priced EGP amount.
3. Student submits transaction reference, sender information, amount, and receipt screenshot.
4. Request remains pending while an admin checks the screenshot and confirms actual receipt of funds, then approves or rejects it with an internal note. A screenshot alone is not proof of payment.
5. Only server-side approval grants access.
6. Admins may create approved cash/manual purchases.

Prevent duplicate approval, amount tampering, replay, and unauthorized receipt access. Store a complete payment and audit history.

Admins may approve full or partial refunds case by case and record them in SEA; funds are returned manually outside the app through InstaPay/Vodafone Cash. Never claim an automatic money transfer or treat approval as proof of completed return. Require an explicit separately recorded access decision (retain or revoke the selected source/scope), not automatic revocation from the refund amount. Preserve immutable purchase/refund history and prevent cumulative refunds exceeding the paid amount. Resolve overlapping-grant revocation scope and operational reconciliation before enabling affected transitions. Store-billed purchases require their applicable platform refund/reconciliation integration rather than fabricated manual settlement.

## Security and access control

Use Supabase Auth, PostgreSQL, RLS, and Edge Functions. The Flutter client must never be trusted for role checks, ownership, payment status, access expiry, progress completion, or signed URL generation. Use least privilege and deny-by-default policies.

Implement:

- Admin role checks and protected admin mutations.
- RLS policies for every table and storage bucket.
- Private receipt/material buckets.
- Short-lived signed URLs for files and video playback.
- Mux or Cloudflare Stream private playback tokens.
- Watermark overlays or watermark metadata using student identity where technically supported.
- Download disabled by default; per-file configuration only when explicitly enabled.
- Students: two registered devices and one active application session; block new admission until current logout. Enabled server-authorized admins: unlimited registered devices and simultaneous sessions. Retain revocation, session validity, disablement and current-role checks for both roles; ordinary logout ends only its own session.
- Rate limits for login, receipt submission, access-token generation, and admin-sensitive actions.
- Input validation, safe file type/size limits, malware-scanning integration point, secure logging, and no secrets in the client bundle.
- Audit logs for admin authentication, content changes, prices, payment decisions, access grants/revocations, device changes, and role changes.

Document that no mobile platform can guarantee prevention of screenshots or screen recording.

## Main features

Student: onboarding, login/register/reset password/email verification, profile, course catalog, search/filter, course details, previews, My Courses, purchased sessions, session player, protected files, progress, resume playback, automatic completion after 90% watched, bookmarks, assignments and homework submission, notifications, and support/contact entry point.

Admin: dashboard, student management, course/session CRUD, media upload, ordering, pricing, previews, publishing workflow, payment queue, receipt viewer, approve/reject, manual purchase/access, revoke access, device management, notifications, analytics, CSV export, audit logs, and soft-delete/restore.

## Suggested data model

Create normalized migrations for profiles, roles, devices, courses, course_instructors, sessions, materials, videos, enrollments, products, orders, order_items, payment_submissions, access_grants, progress, bookmarks, assignments, submissions, notifications, notification_deliveries, audit_logs, and app_settings. Include UUIDs, timestamps, soft-delete fields where appropriate, status enums/check constraints, unique constraints, indexes, and foreign-key behavior. Store money as integer minor units or integer EGP values consistently.

## Architecture and repository quality

Use feature-oriented Flutter modules, Dart models/repositories, typed Supabase data-access services, schema validation, reusable widgets, centralized auth/session state, GoRouter or an equivalent typed navigation approach, error boundaries, loading/empty/error states, optimistic updates only where safe, and accessible form controls. Keep privileged logic in Edge Functions. Add migration and seed documentation. Add `.env.example` and never commit credentials.

## Testing and verification

Add unit tests for validation, entitlement calculation, expiry, progress, device limits, and payment state transitions. Add integration tests for RLS and Edge Functions. Add mobile flow tests for registration, purchase submission, admin approval, content access, revocation, and two-device enforcement. Run typecheck, lint, tests, dependency audit, and a manual security checklist before declaring a phase complete.

## Required project-management files

Maintain `PROJECT_STATUS.md`, `README.md`, and `CHANGELOG.md`. After every meaningful change:

- Update PROJECT_STATUS checkboxes and current phase.
- Record schema/API/security changes.
- Add a changelog entry when behavior changes.
- Record tests run and their result.
- Note blockers and the exact next step.

Never mark work complete without evidence. If requirements conflict, stop and document the conflict instead of guessing.

## Claude Code audit handoff

After each major phase and before release, create an audit handoff containing changed files, database migrations, security-sensitive flows, tests run, known risks, and questions. Ask Claude Code to audit—not rewrite—the implementation for:

1. Authentication, authorization, RLS, and privilege escalation.
2. Payment state-machine integrity and receipt privacy.
3. Signed URL/video entitlement enforcement.
4. Device/session limit bypasses.
5. IDOR, insecure direct object access, data leakage, injection, upload abuse, rate limiting, and secret exposure.
6. Offline/cache behavior and accidental access after revocation.
7. Accessibility, localization readiness, performance, and crash-prone flows.

Claude Code must report severity, evidence, affected files/lines, exploit preconditions, and a recommended fix. It must not silently change production behavior. The Codex agent then triages findings, fixes validated issues, adds regression tests, updates PROJECT_STATUS.md and CHANGELOG.md, and records residual risk.

## Execution order

Start with repository inspection and architecture notes. Use the Agency Agents discovery guidance to consult, in order: Product Manager, UX Researcher/UX Architect, Mobile App Builder, Backend Architect, Security Architect/AppSec Engineer, and Mobile Release Engineer. Use the public `REFERENCE_ANALYSIS.md` only as competitive/product reference material; do not copy its branding or implementation.

Before feature work, verify the Flutter prerequisites listed in README.md: Git, Flutter stable SDK, Dart SDK bundled with Flutter, Android Studio/SDK/emulator, macOS/Xcode/CocoaPods for iOS builds, Supabase CLI, and a private-video provider account. Then implement schema/RLS/auth, core roles, content management, catalog/access, payments, secure media, assignments/notifications, analytics, testing, audit remediation, and release preparation. Keep commits or milestones small and reviewable. At every stopping point, leave the repository buildable and update the status files.
