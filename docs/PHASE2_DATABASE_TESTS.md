# Phase 2 content database regression

Suite: `supabase/tests/phase2_content.sql`. Target: `supabase/migrations/20261018154932_phase2_content_core.sql`, with both Phase 1 identity migrations already present. Contracts: `docs/CONTENT_CONTRACT.md`.

## Execution and results

On 2026-10-18, main reported **PASS 130/130** for an atomic hosted migration-plus-suite rollback preflight. Main then applied the content migration; hosted version is `20261018154932`, and the local migration filename was aligned to that version.

Main subsequently reported **PASS 130/130 against the deployed migration**, a fresh identity suite **PASS 84/84**, and separate cleanup readbacks with all reserved-fixture counts zero. Final main-reported state: zero fixture users, zero real courses, zero real course sessions and one owner administrator. These are main's runtime results; the suite author performed static review only and did not execute SQL against a database, deploy a migration or change the real owner.

Main reported four existing informational private-schema RLS notices and an Auth leaked-password-protection warning because that setting is disabled; no schema warning was reported. Main tracks the Auth setting separately. This suite does not change it, certify that setting, or request an upgrade.

## Running the standalone suite

Use a privileged development database connection with fixture setup rights. Submit the entire suite as one query on one connection; do not run statements as independent connector calls. It starts with `BEGIN`, sets local statement/lock timeouts and RLS, clears legacy claim settings, and switches between `authenticated`, `anon` and the original privileged role. No Auth API, email or Storage API requests are made.

Require the `phase2_test_report` JSON result immediately before `ROLLBACK`: `status=PASS`, `passed=130`, `expected=130`, with all named results. Absence of an error, an empty result, or the cleanup readback alone does not establish a pass.

The full file also includes a read-only cleanup SELECT after rollback. Some connectors return only the last query's result, hiding the assertion report. In that case, main should submit the suite through `ROLLBACK;` to obtain the report, then run the final cleanup SELECT separately. Do not remove rollback or commit fixtures to obtain output. Every cleanup count must be zero.

Any unexpected exception or assertion failure is a failure. If a persistent client stops at an error, roll back on the same connection before reuse, or disconnect. Do not treat partially completed assertions as a pass.

## Atomic migration preflight

Before deployment, main may run the migration and suite in a single outer transaction. Use one `BEGIN`, the migration body, then the suite body after its opening `BEGIN`, through its closing `ROLLBACK`. Omit the post-rollback cleanup SELECT: rolling back the new DDL removes `public.courses` and `public.course_sessions`, so querying them afterwards correctly raises `42P01`.

Main's initial combined attempt hit that post-rollback `42P01`; the corrected composition passed all 130 assertions. This was a preflight composition issue, not a failed content assertion. After deployment, the standalone cleanup query is valid because the content tables persist.

## Assertions and isolation

The 130 named assertions cover:

- Real admitted fixture sessions/device registration and a trusted fixture-only admin grant; forged stored/JWT user metadata still leaves the student role unchanged.
- Active-admin course/session creation and edits, exact integer piasters, ordering and preview fields, required fields, description limits, nonnegative prices/positions, integer overflow and lifecycle state constraints.
- Per-course session-number uniqueness, including soft-deleted numbers; immutable parent, creator, identity and timestamps enforced by column grants. Permanent deletion and arbitrary cover-path writes remain denied.
- One insert audit per fixture entity and exact successful-update audit counts/states. A deliberate exception after a content update proves that the content change and its audit event roll back together. Rejected writes add neither content mutations nor content audit entries.
- Soft deletion forces archive; restoration forces draft even when publication is requested in the same update. Explicit republication is required. A deleted parent blocks session insertion and filters existing-session updates to zero rows.
- Students see only published, nondeleted metadata; draft/archived/deleted items and sessions under unpublished/deleted parents remain hidden. Student insertion fails, updates affect zero rows, and deletion lacks a grant; privileged readback proves data stayed intact.
- Anonymous SELECT/INSERT/UPDATE/DELETE grant denial on both tables. Expired, revoked and ended sessions deny reads and writes for both the server-granted administrator and student.
- RLS enabled on both content tables; the three existing material buckets stay private, and no `storage.objects` policies are introduced. The Phase 1 suite remains a separate regression requirement.

`pg_temp.check_true` runs dynamic SQL with `INTO STRICT`, rejects false/NULL, and records unique assertion names. `pg_temp.expect_error` catches only the tested statement, then compares both SQLSTATE and the full error message outside its exception block; its own assertion failures cannot masquerade as expected denials. Both helpers are SECURITY INVOKER and keep the selected test role. RLS-filtered updates use `RETURNING` counts rather than interpreting silence as success.

Two fictional users reserve `f2c0e100-0000-4000-8000-000000000001` and `...000002`; their Auth sessions reserve `...000101` and `...000102`. Emails use `example.invalid`. Plain fixture INSERT fails on collisions instead of overwriting existing users. Content UUIDs are generated by the database and retained in a temporary mapping; all content updates/deletes target those mapped IDs. Privileged identity/session changes target only reserved fixtures. The real owner is never selected for mutation.

Rollback removes fixture users, Auth sessions, profiles, private accounts/devices/admissions, content, audit rows, helper functions and temporary tables. Post-rollback readback checks users, Auth sessions, accounts, devices, admissions, audit events and both content tables by reserved identity. Event identity sequence values can still advance because PostgreSQL sequence allocation is nontransactional; expected gaps must not be reset. Any project-specific external trigger/webhook effects require separate runner review.

## Limits and review status

No actionable migration defect was identified in this scoped static review, and main reported both preflight and deployed suite passes. This is correctness/RLS regression coverage, not a full security scan. Static inspection does not independently establish runtime results.

SQL claims are supplied directly under test roles; gateway JWT signature/expiry enforcement, HTTP API routing, live Google/email flows, physical logout/new-device acceptance, UI money parsing, uploads, purchases and playback are outside this suite. The deliberate atomicity probe covers rollback after an audited write, not every possible audit-storage failure or concurrent interleaving. Main retains responsibility for deployment, fixture cleanup readback and broader acceptance.

Supabase and Postgres skill guidance informed the distinction between grants and RLS, invoker-role helpers, forged metadata checks and rollback isolation. Reference: [Supabase Row Level Security](https://supabase.com/docs/guides/database/postgres/row-level-security).
