# Phase 1 database integration regression

Target migration: `supabase/migrations/20261016060804_phase1_identity.sql`.
Required follow-up migration: `supabase/migrations/20261016110640_logout_before_registration.sql` (main reports deployed).
Suite: `supabase/tests/phase1_identity.sql`.

## Run once as a single query

The main agent runs this against hosted dev, with the privileged SQL connection used by Supabase `execute_sql`. Read the **entire SQL file** and pass its contents unchanged as the tool's `query` argument, together with the intended dev project ID. Do not split statements across tool calls: temporary objects, transaction state and local roles require one connection. Do not submit through a user-facing RPC or use `apply_migration`. No pgTAP extension is required.

The file starts with `BEGIN`, switches to `SET LOCAL ROLE authenticated` / `anon` for client tests, sets `request.jwt.claims`, and ends with `ROLLBACK`. Legacy individual claim settings are cleared to avoid overriding the JSON claims. Setup and privileged verification use the runner's original role via `RESET ROLE`. Assertion helpers are explicitly SECURITY INVOKER and live only in `pg_temp`.

Success produces a `phase1_test_report` JSON column immediately before rollback, containing `status: "PASS"`, `passed: 84`, and every named result. Intermediate SELECTs can also produce result sets; inspect the report, not the first empty helper result. If the connector suppresses result sets when the last statement is ROLLBACK, retain the full query for a SQL editor/psql run that displays all result sets; never remove rollback to obtain output. Absence of a report is not evidence of a pass.

Any failed assertion raises an exception; unexpected SQLSTATE or message is a failure. A failure aborts the transaction before the final report. If a persistent SQL client stops processing on error, issue `ROLLBACK;` on that same connection before reuse (or disconnect). Never commit failed or successful fixtures. An `execute_sql` call that reports an error must be recorded as failed, even if earlier helper results were returned.

## Fixture isolation and cleanup

Four fictional users use the UUID prefix `f1a5e100-0000-4000-8000-` with suffixes 1–4 and reserved `phase1-N@example.invalid` email addresses. Session suffixes are 101–105, 201, 301 and 401. The script inserts directly into `auth.users` and `auth.sessions`; it does not invoke signup, invitations or email delivery. Plain INSERT fails on collisions rather than altering pre-existing identities.

Storage metadata fixtures use `phase1-regression/fictional-fixture.txt` in the three phase-1 buckets. These are transactional database rows, not uploaded files. All application/auth/storage row changes, temp tables, helper functions and local settings roll back. The script creates no permanent schema objects and does not change policies, grants on application objects, or the migration.

PostgreSQL sequence allocation is not transactional: calls that create security events can advance the existing event identity sequence even when rows roll back. Gaps are expected; do not reset a shared sequence. Existing project-specific triggers/webhooks can have effects beyond the transaction and should be reviewed by the runner if they have been added beyond this migration.

## Assertions and expected denials

| Area | Expected behavior |
| --- | --- |
| Profile ownership | Own SELECT finds one row; UPDATE RETURNING proves all three allowed fields changed. Another user's SELECT/UPDATE finds zero rows, followed by privileged proof that the target is intact. Updating id raises 42501 / permission denied for table profiles. |
| Role escalation | Both stored raw user metadata and JWT user metadata claim admin; returned access context remains student. Private account role update raises 42501. |
| Private data | SELECT and DELETE on all four private tables raise 42501 with the exact permission-denied table message. Direct valid_session execution is denied too. |
| Anonymous caller | All three public RPCs raise 42501 with the exact permission-denied function message. |
| Unverified/banned | Register, context and logout raise 42501 / unverified_or_invalid_session. |
| Disabled account | Register raises account_disabled; context raises session_replaced; profiles are invisible. |
| Registration | Same active session/token is idempotent, with only one device and one start event. A different token raises session_device_mismatch and leaves no new device or changed binding. |
| Device cap | Device 1 login/logout, device 2 login/logout, then new device 3 raises device_limit. An existing device can return with a new session; exactly two non-revoked devices remain. |
| Session lifecycle | A competing session raises active_session_exists and has no profile/context access. Logout removes profile access, prevents updates, and makes re-registration raise session_replaced. |
| Logout before registration | After the competing login is blocked, unregistered valid session 105 calls end_session twice. Its later registration raises 42501 / session_replaced, its tombstone has NULL device_id and non-NULL ended_at, and exactly one logout event exists. No device is added. Session 101 retains its active pointer, access context and readable profile before the existing logout/device-cap tests continue. |
| Server-session validity | Missing UID raises authentication_required. Missing session claim, another user's session, deleted session and expired session raise unverified_or_invalid_session. Expired/deleted registered sessions also lose profile visibility. |
| Storage | Assert RLS enabled, no storage.objects policies, and all three buckets private. Under an active authenticated account, each bucket's seeded object is invisible; UPDATE matches zero rows; INSERT raises 42501 / new row violates row-level security policy for table "objects". Direct DELETE raises 42501 / Direct deletion from storage tables is not allowed. Use the Storage API instead. These DELETE tests verify the platform's storage.protect_delete() trigger, not row-policy filtering. Privileged read proves all seeds intact. |

The expected-error helper catches only errors from the tested statement. It compares both SQLSTATE and the complete message outside the handler, then records PASS. Its own “statement succeeded” or mismatch exception cannot be caught as an expected failure. Boolean assertions reject NULL as well as false and require exactly one result row. RLS-filtered writes use RETURNING/count checks, not “no exception” checks.

## Concurrency coverage and remaining tests

The single transaction simulates a second login **sequentially**. It checks rejection while a first session is active, but cannot prove row-lock behavior, races or isolation across connections.

On 2026-10-16, main separately reported a hosted-dev **parallel request admission test**: committed fictional user sea-concurrency@example.invalid (reserved UUID f1c0a100-0000-4000-8000-000000000001), two auth.sessions with suffixes 101/102, and two execute_sql transactions dispatched with Promise.all. Each transaction set role authenticated and its JWT claims, registered a distinct device token, then held the transaction with pg_sleep(2) before commit. Observed result: one success and one SQLSTATE 42501 / active_session_exists. Main queried exactly one active session and one device, removed the fixture user and its audit events, and verified zero remaining fixtures. This establishes the observed parallel admission outcome only; it is not proof of exhaustive interleavings or measured lock-wait behavior.

For remaining coverage, use a disposable/local database with this migration and fixtures visible to two independent connections. This requires committed setup, so it cannot share the rollback-only fixture strategy above. Have connection A register session A and hold its transaction open. Have connection B register session B for the same account. Confirm B waits on the account lock; commit A; then confirm B fails with 42501 / active_session_exists and only A is active. Repeat from fresh state with A rolled back: B should then succeed. Race new-device registrations with a pre-existing device to verify the count never exceeds two, and race logout against login to inspect both serialization orders, including logout before the first registration. Clean up disposable state after each case. Main coordinates these separately; these additional scenarios have not been reported as passed.

## Findings and verification status

On 2026-10-16, main reported that the updated suite passed **78/78 assertions on hosted dev**. Main's first hosted run failed at the course-materials DELETE assertion because storage.protect_delete() rejected direct deletion with SQLSTATE 42501 and the exact message above. Main confirmed fixture_users_remaining=0 after that failed run. All three DELETE assertions now expect that platform error; no protection is bypassed, disabled, or dropped.

Final runtime status, 2026-10-16: main reported **PASS 84/84 on hosted dev** after applying `20261016110640_logout_before_registration.sql`. This supersedes the earlier 78-assertion run and includes the logout-before-registration regression. Main also reported that the security advisor returned only the same four informational private-schema RLS notices.

The test author did not execute this suite against hosted dev; runtime evidence above was supplied by main. Static review checked the assertions against both reconciled migrations; no migration edits were made. PostgreSQL parser validation (pglast) passed for all 162 top-level statements and all 84 embedded assertion queries in the expanded suite. Assertion names are unique; transaction boundaries remain BEGIN/ROLLBACK. This syntax check does not execute PL/pgSQL bodies or validate deployed privileges, triggers, or policies.

Coverage exclusions: no email was sent by these SQL tests, and email signup, delivery, verification links, and recovery flows were not tested. Google OAuth/sign-in was not tested. Concurrency evidence is limited to the separately reported parallel request admission test above; no exhaustive concurrency claim is made.

Resolved static concern: logout before registration previously stored no ended-session marker and could lock no account row. Main's follow-up migration creates the account row before locking, inserts an ended-session tombstone, and logs only a newly ended session. A NULL device_id is permitted only for an ended session. The hosted 84/84 pass confirms the regression's tombstone, delayed-registration rejection, single logout event, and preservation of the other active session. The absent-account branch and actual logout/register interleavings remain separate coverage limits, not unresolved findings; session 105 intentionally belongs to an already registered account. PostgreSQL locks only rows retrieved by SELECT FOR UPDATE: [row-lock semantics](https://www.postgresql.org/docs/current/explicit-locking.html#LOCKING-ROWS).

No unresolved migration defect is recorded by this review. Operational context and coverage limits:

- The migration creates closed buckets but does not remove existing storage policies. This suite intentionally fails its no-policy precondition if unrelated/broad object policies exist; investigate deployed policy scope rather than weakening the assertion.
- The repeated-logout audit-noise concern is resolved by the follow-up migration's affected-row check. The hosted regression passed the assertion of exactly one logout event after two calls for session 105.
- The migration checks `auth.sessions.not_after`, not a forged JWT `exp` supplied in SQL. JWT signature/expiry validation belongs to the API gateway and needs an HTTP-level test; this file tests database authorization with supplied claims.

The Supabase skill informed role isolation, unsafe user-metadata checks, server-session checks and the distinction between RLS filtering and privilege errors. References: [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [Supabase changelog](https://supabase.com/changelog).
