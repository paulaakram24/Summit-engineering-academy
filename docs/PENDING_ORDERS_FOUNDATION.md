# Staged pending-order foundation — 2026-10-21

This slice prepares private data contracts only. Creation stays **closed to client roles** until remaining business decisions and payment prerequisites are resolved. It does not enable checkout, transfer instructions, receipt submission, approval, refunds, grants or protected learning. Course/session intents are an initial engineering slice; editable bundle integration remains required later.

Owner resolved the main morning rules on 2026-10-21: reuse unpaid target requests, block targets already covered by valid access, honor existing price snapshots, reject unavailable targets before approval with manual refund handling for received funds, and source-only refund revocation. Admin learning access needs no purchase. Receiving phone/method configuration is per assigned course instructor, not global; instructor chooses InstaPay bank-account transfer only or that plus Vodafone Cash at the same number. These are new requirements, not behavior delivered by the staged migration below. Creation remains closed until repeat-request/access checks, trusted instructor association, versioned receiving details and payment prerequisites are implemented/tested.

## Frozen API projection

An order intent has exactly: `id`, `kind`, `course_id`, `session_id`, `course_title_snapshot`, `session_title_snapshot`, `price_piasters`, `currency`, `state`, `created_at`.

Kinds are course/session; course intents have null session fields. Currency is EGP, price is server-supplied integer piasters, and pending means intent only, not submitted/received payment. Creation validates current published/nondeleted parents and snapshots title/price under locks. History exposes only immutable original titles/price, not current hidden descriptions, outlines or material payloads. Never infer learning ownership from this model.

- `create_pending_order(p_kind, p_target_id, p_operation_id)` is defined but both public wrapper and private creation helper have no execution grants to anon/authenticated/service_role or PUBLIC. A future reviewed migration must deliberately enable creation; adding a mobile button is insufficient. Rollback tests may temporarily grant execution only inside their fixture transaction.
- `get_own_order(p_order_id)` returns only the active actor's safe snapshot or null; another owner's ID and a missing ID are indistinguishable. Admins get no cross-owner history exception.
- `list_own_orders(p_before_created_at, p_before_id, p_limit)` uses paired descending created_at/UUID cursor, default 20/max 50, and exact items/has_more/next_cursor envelope. No totals reveal another account's history.

## Invariants

Private RLS/explicit grants remain separate boundaries. Creation's narrow private definer helper rechecks active admission and authoritative Student role, derives buyer and prices, and uses empty search path/qualified references. The public wrapper is invoker. Clients cannot write order snapshots, buyer, price, status or operation ledger directly.

Serialize the actor operation and validate request identity. Same actor/operation/input returns the original committed safe snapshot after current authorization checks, even if the price or publication changed afterward. Changed operation input fails. Record the order, operation result and one safe audit event atomically; failure rolls all back. Immutable snapshots/ledger preserve provenance through content soft deletion. Distinct-operation repeat purchase eligibility is not settled by operation idempotency; execution remains closed while that policy is unresolved.

Student creation eligibility in rollback tests does not authorize admin purchasing or self-approval. Own history can remain readable after an account is promoted, subject to current admission. Zero-price intents still grant nothing. No actual order or real money flow should be created during development acceptance outside isolated fixtures.

## Client boundary

Strict immutable Dart models and descending cursor/page validation reject extra/internal fields, invalid UUIDs, inconsistent course/session combinations, noninteger/out-of-range prices, non-EGP currency, any non-pending state, invalid/timezone-less/calendar-rollover timestamps and malformed cursor boundaries. Preserve microseconds; a pending label can never imply approved payment.

The subsequent read-only transport exposes getOwnOrder(actorId, orderId) and listOwnOrders(actorId, cursor, limit), calling only the two history RPCs. actorId is a required local guard, never a server buyer parameter. Capture a valid GoTrue session, pin its JWT on that request, and discard results/errors after actor switch including switch-away/back. Reject mismatched detail IDs and page boundaries; return fixed failure messages, with no cache, table fallback or automatic retries. There is no creation method, screen or runtime injection.

## Acceptance and gates

Verified development checkpoint: migration 20261021002402, SHA-256 0BC4E6C9E65608CBD15F7A23EDD56E6947A740B533F9FD018209E32D583FDF6E. All nine rollback suites passed before and after deployment (814 assertions, 70 here); fixture and actual order/operation counts are zero. Hosted role privilege readback confirms both creation entry points closed. Anonymous HTTP creation/detail/list each denied 401/42501. Strict models passed 32 focused tests; full app suite 617, analysis/58-file formatting and configured debug build passed. No transport/UI or real concurrency acceptance is included in that checkpoint.

Preflight harness note: its first composition matched the word BEGIN; inside a test comment and failed SQL parsing. No schema was installed by that failed transaction. Anchoring insertion to the actual BEGIN; line corrected the harness; the complete successful preflight preceded deployment. The checked-in migration did not need a SQL fix for this runner error.

Later transport acceptance: 35 new focused tests, 67 combined model/transport tests, full app 652 tests, clean analysis, 61-file zero-change formatting and configured Android debug build (3.1s). Independent frozen-file review found no concrete blocker. APK bytes/hash unchanged from cleanup because no order runtime is imported; no new native order acceptance is claimed. Backend remained unchanged after 814 successful postdeployment assertions.

Security advisors retain the prior seven intentionally closed private-RLS INFO findings and leaked-password-protection warning. Performance advisors add two initially unused course/session order-FK indexes to the prior three unused indexes and material composite-FK INFO; keep the FK indexes rather than removing them to silence a new empty-table advisory. See [RLS notice guidance](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), [password protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection), [index guidance](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index) and [foreign-key indexing](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys).

Require exact-count rollback reports, fixture cleanup, authorization/forged role/cross-owner/hidden parent tests, immutable snapshots, idempotent retry/changed-input rejection, audit-failure rollback and pagination. Sequential tests do not prove real parallel-transaction behavior. Existing app/backend regressions must still pass. Actual deployment, model checks and artifacts are recorded in PROJECT_STATUS.md only after they run; file existence alone is not acceptance.

Before enabling creation or checkout, resolve MORNING_QUESTIONS.md and obtain payment destinations at 3.2. Receipt storage, verification, bundle selection, refunds and entitlement integration need their own reviewed milestones. Keep production signing/distribution and store/iPhone gates separate.

Independent audit instructions are in PHASE3_STAGED_AUDIT_HANDOFF.md. This prepared handoff is not an executed Claude Code audit.

The separate instructor-payment setup foundation is now development-deployed and tested; see INSTRUCTOR_PAYMENTS.md. It does not enable order creation, enforce unpaid-request reuse, issue destination snapshots or implement pause/review transitions. The existing ten-field order projection remains unchanged and contains no receiving data.
