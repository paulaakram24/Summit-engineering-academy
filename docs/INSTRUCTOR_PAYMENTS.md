# Instructor payment setup — foundation and admin configuration

## Confirmed owner requirements — 2026-10-21

Each course has one explicitly assigned existing Admin account acting as instructor. Its sessions and same-course bundles use that instructor; cross-course bundles are not allowed. Instructors manage their own receiving details: phone number and recipient name only, with InstaPay-only or InstaPay plus Vodafone Cash at the same number. Do not add a bank-name field or infer identity from course display text/creator.

Changing receiving details or the assigned instructor must not silently redirect an issued request. Existing unpaid requests pause for instructor review before new instructions; preserve old instructions, original price and any transfer/refund history. The current staged order system issues no instructions and creation remains closed, so the review transition must be implemented before checkout is enabled.

Admin learning access needs no purchase or approval, but remains separately server-authorized under current admission and resource safety/readiness. This setup foundation does not implement learning delivery.

## Frozen setup contract

All setup endpoints require active server-authorized Admin admission. No anonymous/Student receiver directory or payment instructions are exposed. No direct client writes to private tables.

- Profile: exactly instructor_id, recipient_name, phone_number, method_configuration, revision. method_configuration is instapay_only or instapay_and_vodafone_cash. Same phone serves both when enabled.
- get_my_instructor_payment_profile() returns own current profile or null. No arbitrary owner parameter.
- save_my_instructor_payment_profile(p_recipient_name, p_phone_number, p_method_configuration, p_expected_revision) returns own profile; buyer/instructor identity comes from auth.uid().
- Binding: exactly course_id, instructor_id, revision.
- get_course_payment_instructor(p_course_id) returns binding or null for an existing nondeleted course; missing/deleted course is unavailable.
- set_course_payment_instructor(p_course_id, p_instructor_id, p_expected_revision) assigns an enabled verified Admin with a configured receiving profile. Any currently authorized course-admin may select the course's instructor; only the instructor edits their own receiving profile. Sessions inherit via their immutable parent, never a separate payment override.
- list_payment_instructors(p_after_id, p_limit=20) returns exact items/has_more/next_cursor, ascending instructor UUID, max 50. Each item has instructor_id and display_name only; next_cursor has instructor_id. Return enabled verified Admins with configured profiles, no phone, recipient, methods or bank fields.

Directory display_name is the existing public profile name, ASCII-space-trimmed, nonempty and at most 120 Unicode codepoints with no NUL. Unlike receiving names, existing profile display names may contain line breaks/control characters; do not reject an otherwise valid directory page by applying recipient-name rules there. Never substitute private recipient_name for a missing display name.

Profile names are ASCII-space-trimmed, 1–160 Unicode codepoints, no ASCII control characters. Phone values are canonical optional leading plus and 7–15 ASCII digits, without formatting. This is syntactic validation only, not verification that a number can receive bank/wallet transfers. The app may later normalize explicitly allowed presentation characters before submission; do not invent a bank capability check.

Current profile/binding revisions start at 1; expected_revision=0 creates an absent record. Every accepted change advances exactly once under row locks and appends immutable private revision history plus a safe audit event. Stale/overflow fails without partial history/audit. Preserve prior receiving details only in protected history; audits contain actor/target/revision identifiers, never phone/name/bank details. No direct history grants to clients.

Public wrappers are invoker with fixed empty search path and explicit grants; any narrowly necessary definer helper stays private, validates authoritative role/admission, and has qualified references. Private tables have RLS, explicit privileges and indexed FK paths. Revocations must prevent anonymous/default PUBLIC execution. Recheck relevant role/disable state under deterministic account-row lock ordering before mutations.

Failure contract: 42501 payment_setup_access_required, payment_setup_target_unavailable, payment_setup_state_conflict; 22023 invalid_payment_setup_input. Avoid exposing whether an unavailable instructor is disabled, nonexistent or a Student.

## Scope and gates

The database/model foundation is followed by the actor-pinned transport and administrator setup screens below. Student instructions, real receiving values, real-course assignments, bundle schema, receipt uploads, order enablement, approvals, refunds and grants are not delivered by setup alone. Do not modify deployed order/catalog projections to carry recipient data.

Tests must cover own-only profile writes/reads, other-admin denial of profile data, safe directory, disabled/demoted/unverified/nonanonymous identity, inactive admission, Student/anon denial, CAS/history/overflow, immutable history, atomic audit-failure rollback, hidden private data, missing/deleted courses and directory pagination. SQL fixtures are fictional and rolled back. Real parallel interleavings and native setup acceptance remain separate gates.

After setup UI acceptance, implement reviewed destination snapshots/paused-request transitions, repeat/ownership checks and same-course bundles before enabling checkout. Record actual results in PROJECT_STATUS.md; no completion follows from this contract alone.

## Model checkpoint

Pure models passed 32 focused tests. Main full app checks passed 710 tests, clean analysis, locked dependencies, 65-file zero-change formatting and configured Android debug build (33.3s). Current APK: 189074810 bytes, SHA-256 0CA3C56D9359D210B27F5043A1EBB0068FF5950B1012BD8FA92B76757D97759A. This artifact is not installed/accepted on a device in this setup checkpoint; the preceding appearance native evidence belongs to its separately recorded artifact. No setup transport/UI is imported into runtime.

Review separated existing profile display-name validation from the stricter receiving-name validation, avoiding rejection of otherwise valid directory names. Binding's initial-row serialization uses an exclusive parent-course lock after ordered account locks; source inspection is not real parallel-transaction evidence. Database acceptance will be recorded only after the exact-count suite/preflight run.

## Verified database foundation — 2026-10-21

Development migration 20261021085143, file SHA-256 825A8C6E4B180E01EEE068E31C787C8900C0E4337B358268286F7FBF3FDA445C. All ten rollback suites passed both additive rollback preflight and postdeployment, 893 named assertions (79 setup, with an exact count guard). The initial draft estimate of 83 was corrected to 79 actual assertions before acceptance. Final bounded review found no concrete SQL/model blocker. Role identity is server-owned, soft-deleted payees are excluded, and ban expiry at the current timestamp is handled consistently.

Hosted readback confirms zero rows in all four real setup tables, zero actual orders/operations, and zero reserved fixture users, sessions, account access, devices, admissions, public profiles, security events, courses, orders and operation records. All five setup RPCs denied anonymous HTTP calls with 401/42501. Creation remains closed at both old order entry points.

Security advisors add two RLS/no-policy INFO notices for deliberately inaccessible private history tables (nine total), not a reason to grant direct reads. Existing leaked-password protection warning is unchanged. Performance adds four initially unused FK/history indexes (nine unused indexes total), retaining the prior material composite-FK INFO. See [RLS notice guidance](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection), [unused indexes](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index) and [FK indexes](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys). No broader grants, index removal or paid setting change was used to silence notices.

This database evidence completes the private setup foundation only. Real receiving values, course assignments, request-bound instructions/pause review, bundles and payments remain separate gates. No push is authorized by these test/deployment results.

## Administrator setup integration — 2026-10-21

The configured app now injects SupabaseInstructorPaymentRepository. Administrator home opens **Receiving payment details**, with required recipient name/canonical phone and the two allowed method configurations. Manage courses opens **Payment instructor** for a nondeleted course. Its paginated directory exposes only display names and disambiguating UUID text. Sessions have no receiving override. Student home exposes neither setup entry.

Each request pins the initiating JWT without changing global headers or sending an actor/owner parameter. Responses must match the initiating account/course and mutations must acknowledge exact fields plus expected revision + 1. Unknown backend errors are sanitized. Account switches, including switch-away/back, invalidate in-flight replies. No cache, table fallback or automatic retry is provided.

Panels capture access-object identity, account, device, lifecycle and operation epoch. Access/dependency changes clear private state and owned dialogs, with stale replies and retained callbacks blocked. Saves/assignments require explicit confirmation and a fresh read after success; uncertain failures require manual refresh, never another automatic mutation. Dirty Back/Close asks before discarding. A readback does not verify actual bank/wallet receiving capability.

Agency Agents Mobile App Builder implemented the receiving form, Course Assignment Engineer the selector, and Mobile Release Engineer performed bounded read-only review. Review caught an unrelated-route pop from retained assignment-dialog callbacks; exact owned/current-route guards and regression tests were added before acceptance. Main owns runtime wiring and transport/integration checks. This is not an executed Claude Code audit.

Main final verification passed 834 app tests: baseline 710 plus 42 transport, 44 receiving UI, 34 assignment UI and four entrypoint tests. Analysis, locked dependencies, 73-file zero-change formatting and configured Android debug build passed (8.6s). Final APK 189134273 bytes, SHA-256 AA43F2E4644421DD7CA8F565201E8597FE0C107BF6737E38ECCAF9ED24BB7672; installed base hash matches. Bounded emulator evidence and its exact artifact scope are recorded in PROJECT_STATUS.md. No live save or assignment is authorized merely by exposing these controls; the owner must supply their actual values and make an explicit confirmed choice. Checkout remains closed until the separate order-instruction/review/bundle/ownership gates pass.

Final artifact native acceptance: retained administrator welcome, own unconfigured form, required-field rejection and fully wrapped phone error, then Close without saving. Emulator DNS initially failed after the host/tool stall; a data-preserving cold start with emulator-only public DNS restored network resolution. Windows DNS/account storage were not changed. Earlier artifact B9AF1308…C16670 separately accepted the unassigned/empty instructor directory and unsaved method-selection cancellation/discard. Neither exercise saved a receiving destination or assignment. Screenshots/logs remain outside the repository; no contact information is committed.
