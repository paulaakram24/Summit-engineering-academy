# Closed order foundation and saved-reference cleanup — audit handoff

Prepared 2026-10-21. This is an independent audit request, **not an executed Claude Code audit**, payment readiness or Phase 3 completion. Read the newest PROJECT_STATUS.md first. Cleanup and closed-order work is now pushed as bb617fa; review that snapshot and relevant later working-tree changes **including untracked files**, without treating unrelated appearance work as payment implementation. Do not edit, commit, push, change roles/sessions, publish courses, enable creation privileges or mutate hosted data during review.

## Scope

- Latest client setup scope: instructor_payment_repository.dart, supabase_instructor_payment_repository.dart, both instructor setup panels and tests, plus main.dart/AuthPanel/AdminContentScreen wiring. Main passed 834 tests, clean analysis/formatting and configured Android debug build; exact final artifact/native limits are in PROJECT_STATUS.md. Trace initiating JWT pinning, A–B–A rejection, exact CAS acknowledgments, private-field clearing, uncertain result manual refetch, owned/current-route confirmation callbacks and required-field readability. The bounded review's retained assignment-dialog pop was fixed with regression tests; this is not an independent Claude Code execution. Receiving-change request pauses/bundles remain unimplemented.

- Latest additional setup scope: docs/INSTRUCTOR_PAYMENTS.md, migration 20261021085143_phase3_instructor_payments.sql, supabase/tests/phase3_instructor_payments.sql, app/lib/commerce/instructor_payment_models.dart and model tests. All ten suites passed preflight/postdeployment (893 assertions, 79 setup); full app 710 tests/build passed. Own-only receiving profile, explicit course binding and metadata-only directory must not leak phone/recipient information, infer a payee from creator/display text, or enable old order creation. Check same-course bundle/paused-request policies as requirements, not implemented transitions. No real receiving values/assignments/orders were created. Source review corrected initial binding serialization and display-name validation before acceptance; true parallel interleavings remain open.

- Saved-reference cleanup: migration 20261021001423_phase2_bookmark_cleanup.sql, supabase/tests/phase2_bookmark_cleanup.sql, app/lib/bookmarks/, app/lib/catalog/catalog_screen.dart and bookmark tests.
- Pending intents: migration 20261021002402_phase3_pending_orders.sql, supabase/tests/phase3_pending_orders.sql, app/lib/commerce/ and order tests.
- Baseline identity/admission, authoritative roles, admin parallel-session policy and prior bookmark revision/tombstone contracts.
- CI migration order and all rollback suites, not just newly added tests.
- docs/PENDING_ORDERS_FOUNDATION.md, docs/SAVED_COURSES_DESIGN.md, docs/MORNING_QUESTIONS.md and docs/SUPABASE_OCTOBER_2026_NOTICE.md.

## Questions to trace

1. Are both public/private creation entry points actually closed to PUBLIC, anon, authenticated and service_role? Does a future grant need a deliberate migration rather than a UI change? Keep tests' temporary grants wholly inside rollback transactions.
2. Are buyer, authoritative Student role, admission, content visibility and integer-piaster price derived on the server? Can metadata, caller-supplied owner/price, hidden parents or direct table access bypass them?
3. Do actor/course/session locks keep snapshot selection consistent, and does a failed audit insert roll back order and operation result? Distinguish sequential evidence from untested parallel interleavings.
4. Does same-actor/operation/input replay return only the original safe snapshot after current admission/role checks? Does changed input fail? Do not confuse operation idempotency with the unresolved repeated-purchase/ownership policy.
5. Can admins or another buyer infer someone else's order through detail/list, totals, errors or cursor behavior? Are immutable original title/price snapshots separated from current hidden descriptions and protected payloads?
6. Are history pages exact ten-field projections with paired descending timestamp/UUID cursors, bounded limits, no duplicate/nonadvancing boundary and microsecond-preserving client parsing? Check timezones, calendar rollover, invalid UUIDs and extra internal fields.
7. If read-only transport exists in the current tree, does it expose only detail/list, capture and pin the initiating actor's token, and reject account changes including switch-away/back? Check error/timeout paths and ensure no raw backend details or tokens escape. No runtime integration is authorized merely by this audit.
8. Does bookmark cleanup change only the active owner's unavailable saved=true references, retaining false tombstones and advancing revisions atomically? Does overflow roll back the whole operation without leaking hidden IDs?
9. Does its explicit owned confirmation route cancel safely on account/lifecycle changes, leave unrelated routes untouched, prevent duplicate submission and require refresh after an uncertain result?
10. Do new objects define explicit table/function privileges independently of RLS, including after the announced October 30 default-grant change? Do not apply blanket grants to silence an advisory.

## Recorded evidence and limits

At the initial closed-foundation checkpoint: all nine hosted rollback suites passed both additive rollback preflight and postdeployment, 814 named assertions (70 order, 29 cleanup). Actual order/operation and reserved fixture counts were zero. Anonymous creation/detail/list and cleanup HTTP calls were denied 401/42501. Full Flutter suite passed 617 tests including 32 model tests; analysis, locked dependencies, 58-file zero-change formatting and configured Android debug build passed. Later transport results must be read from current status, not inferred from these counts.

Cleanup native acceptance is bounded to the retained administrator emulator session: installed/hash-matched artifact, dialog/cancel and confirmed zero-row result/refreshed list. Hosted bookmark count was zero before/after; no real saved data was removed. Populated/student/TalkBack/Huawei/signed-release and real parallel-transaction testing remain separate gates.

No checkout, receipt storage, payment approval, refund transfer, bundle coverage, entitlements or protected learning is enabled. Pending means intent only, never paid/approved. Morning policy questions and four instructor follow-ups are resolved in docs/MORNING_QUESTIONS.md; their implementation and acceptance must be checked separately. Existing password protection warning and intentional private-table RLS INFO findings are tracked, not silently fixed through broader access or paid configuration.

## Required report

Give severity, verified file/line, concrete path and prerequisites, impact, minimal fix and regression test for each actionable finding. Separate demonstrated failures, hypotheses needing runtime evidence and nonblocking improvements. Do not print credentials, contact information, session tokens or OAuth URLs. No account/installation/subscription changes are authorized. Codex will triage findings and record fresh evidence before asking for another push.
