# Catalog database contract and rollback regression

## Main execution result — 2026-10-20

Main independently executed the complete catalog transaction through its included rollback on development migration **20261019193939**. The exact report returned status PASS, passed/expected **155**, and all 155 named assertion entries PASS; twelve separate reserved-fixture cleanup counts were zero. Existing identity/content/cover/material suites were rerun separately and passed **84/130/53/163**, bringing the fresh database total to **585 assertions**. This supersedes pending execution statements in the historical handoff below; it is postdeployment development verification, not atomic schema preflight, signed-in HTTP or physical student acceptance. Existing owner data and the authorized recoverably deleted temporary course remain outside all mutation scopes.

The workflow now includes the catalog suite for the next approved push; that future workflow change has not run remotely. The preceding editor push f79f359 passed both remote workflows without this new catalog increment.

Security advisors remain seven intentional private-schema RLS/no-policy notices and the existing [disabled leaked-password protection warning](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection). Performance advisors retain [unused development indexes](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index) and the existing [composite material payload foreign-key index notice](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys); material_id is already a unique primary key bounding parent lookup to one row. No policy was broadened, paid setting enabled or index removed to suppress a notice. Catalog functions reuse existing ordered course/session indexes; this is not measured production performance acceptance.

2026-10-19. Scope: roadmap 2.4.1/.2, read-only course catalog, course details, ordered session outlines and server search/filter options. No entitlement, payment, material projection, media delivery or client implementation is included in these files.

## Files and execution status

- Migration: `supabase/migrations/20261019193939_phase2_catalog.sql`.
- Regression: `supabase/tests/phase2_catalog.sql`.
- This document: `docs/CATALOG_DATABASE_TESTS.md`.

The author generated the original filename `20261019193637_phase2_catalog.sql` using the existing pinned CLI at `E:/CodexNpmCache/_npx/5ed57a240faae6e6/node_modules/@supabase/cli-windows-x64/bin/supabase.exe`, after reading `migration new --help`. Main subsequently reported successful additive deployment through the connector and hosted migration-list verification of **20261019193939**, then renamed the local mirror with a header-only change. The old filename is gone; do not recreate it. The migration was frozen after main/independent review; the suite author made no subsequent migration changes.

**This was not atomic migration preflight.** Main deployed the additive migration first and will run the fixture regression against that deployed version. The suite rolls back its fixtures, not the already deployed functions. Main reported no local Docker verification because WSL is unavailable. The suite author performed no hosted query, deployment, local database execution, dependency installation, client/status/workflow edit or push. Deployment evidence is main-reported; a runtime regression PASS is still pending until main records the exact report and cleanup results.

Prerequisites: both identity migrations, content core `20261018154932`, cover migration `20261019015308`, and admin materials `20261019154009`. The materials prerequisite is needed for the denial/canary fixtures, although catalog functions themselves never read materials.

## Exact RPC contract

All four functions return JSONB, are **STABLE SECURITY INVOKER**, set `search_path=''`, use fully qualified relations/helpers and check `private.is_active()` before returning data or validating caller input. They retain underlying course/session RLS. Anonymous/PUBLIC EXECUTE is revoked and authenticated EXECUTE granted; table privileges, RLS policies and Storage policies are unchanged.

| RPC | Arguments / defaults |
| --- | --- |
| `list_catalog_courses` | `p_search text=''`, `p_category text=null`, `p_level text=null`, `p_after_position integer=null`, `p_after_id uuid=null`, `p_limit integer=20` |
| `list_catalog_sessions` | Required `p_course_id uuid`; `p_after_position integer=null`, `p_after_id uuid=null`, `p_limit integer=20` |
| `get_catalog_course` | Required `p_course_id uuid` |
| `get_catalog_filters` | No arguments |

List envelope has exactly `items`, `has_more` and `next_cursor`. Each query filters before pagination, fetches at most limit+1 ordered rows, returns at most limit, and uses the **last returned** row for `{position,id}` only when another row exists. Terminal/empty pages have `has_more=false,next_cursor=null`; empty items is `[]`, never null. Both positions and UUIDs sort ascending. The session order is `(position,id)`, deliberately not session-number order.

Course objects contain exactly `id,title,description,instructor,category,level,price_piasters,position,cover_path`. Session objects contain exactly `id,course_id,session_number,title,description,price_piasters,position,is_free_preview`. Course detail returns that same course projection or SQL NULL for an unknown/draft/archived/deleted course. Unknown or hidden-parent outlines return the ordinary empty envelope. Explicit null course IDs are invalid input, not unavailable content.

Search is a case-insensitive **literal substring** of title, instructor or category, using lowercase plus `strpos`; `%`, `_`, backslash and SQL-looking text have no wildcard/executable meaning. Description, level and material content are not search fields. Trimming means PostgreSQL `btrim` of ordinary ASCII space U+0020 only, matching the resolved client contract. Omitted search defaults to empty; explicit null search is invalid; trimmed search is limited to 100 characters. Tabs/newlines are not silently trimmed.

Category/level are nullable, trimmed to at most 120 characters, and blank normalizes to null/no filter. Nonblank filters compare exactly and case-sensitively against the space-trimmed stored fields. Course projections retain the original authored field values. Limits must be nonnull integers 1–50. Cursor components must both be null or both present, with position nonnegative; the UUID is a typed boundary value and need not still identify a visible row.

`get_catalog_filters` returns exactly `{categories:[text],levels:[text]}` from the **full published, nondeleted catalog**, independent of list search/category/level/cursor. Values are trimmed, distinct, and sorted using SQL `COLLATE "C"`. Empty arrays are `[]`. ASCII fixtures verify order; clients should preserve server order rather than require Dart UTF-16 comparison to reproduce SQL ordering for every Unicode character.

Course/session prices and positions remain database int32 values 0–2,147,483,647; session numbering is 1–2,147,483,647. EGP prices are authoritative integer piasters, never floating-point calculations or proof of access. The fixture includes zero values, valid int32 maxima and invalid negative/overflow probes. A preview flag is metadata only; it does not issue playback access.

Inactive/nonadmitted, disabled, revoked, banned, unverified or invalid-session authenticated callers get **`42501 / catalog_access_required`**, never an empty catalog. Invalid typed input from an admitted user gets **`22023 / invalid_catalog_input`**. Malformed UUIDs and values outside the SQL integer type fail PostgreSQL argument coercion before function-body validation; clients should validate those shapes/ranges as well. Anonymous callers fail function EXECUTE privileges. Authorization precedes input checks inside each function.

## Security and projection pitfalls retained in the contract

- Existing course/session RLS permits administrators to inspect drafts in authoring. Every catalog query additionally requires published/nondeleted course state; outlines also require published/nondeleted session state. Administrators cannot use these catalog RPCs as draft previews.
- SECURITY INVOKER intentionally uses caller grants and RLS. No SECURITY DEFINER view, privileged table lookup, new student material policy or ordinary-role upgrade is introduced. Explicit RPC field allowlists do not remove existing direct course/session SELECT privileges; restricting those further would require a separately reviewed admin-compatibility change.
- There is no `SELECT *`/whole-row JSON return, creator identity, timestamps, deletion/status internals, material body, private link URL, provider UID, file key, purchase state or media capability in the projection. Approved descriptive course/session text is still authored content; field allowlisting cannot detect an administrator manually pasting a secret into a description.
- `cover_path` is the existing course-scoped immutable PNG image reference exception. Existing schema constraints reject arbitrary URLs and nonimage paths; actual reads still use authenticated cover Storage RLS. The suite creates only a valid reference with no corresponding object/reservation, exercising metadata/fallback without uploading. Do not convert it into a public bucket URL or use that exception for paid files.
- `session_materials` remains admin-only, private payload/operation tables remain closed, and all material/receipt/submission buckets remain private. Catalog APIs do not join those tables or issue signing, downloads or playback.
- Keyset pagination is deterministic for an unchanged ordering, **not a snapshot across concurrent position edits**. Clients must reject duplicate IDs/nonadvancing pages, reset cursors on criteria changes, and discard stale responses after query/account/admission changes. This SQL suite cannot establish client behavior or absence of cross-account UI/cache races.

## Regression inventory and expected report

Expected total: **155 uniquely named assertions**: 115 explicit checks plus four RPC denials for each of ten invalid-admission scenarios. All assertion helpers are SECURITY INVOKER. Query-read helpers `pg_temp.catalog_saved` and `pg_temp.catalog_keys` are STABLE, not IMMUTABLE, to avoid stale fixture/page snapshots. Check helpers require exactly one true boolean using `INTO STRICT`; error helpers compare complete SQLSTATE and message outside the caught tested statement. Result names are a primary key, and the final count guard raises unless the exact expected total exists.

Coverage:

- Twenty-five released courses and twenty-five released sessions span 20+5 pages, equal-position UUID ties, later-page matches, exact-size terminal pages, limit 1/50, max-int32 cursor boundaries and empty results. It proves last-returned-row cursor semantics, no sentinel leakage and unique IDs over an unchanged fixture ordering.
- Literal search, case folding, space-only trim, instructor/category search, exclusion of descriptions, combined filters before pagination, blank clearing, exact-case filters, option values beyond page one and full-catalog SQL-C ordering. Wildcard-negative probes ensure `%`/`_` cannot expand to arbitrary title text.
- Exact course/session/envelope/cursor/filter key allowlists, nullable and validated image references, zero/max prices, max/min session numbering, hidden child/parent state, unknown IDs and explicit republication after restore-to-draft.
- Anonymous EXECUTE denial; admin catalog draft exclusion despite authoring visibility; active student reads despite forged admin metadata; disabled administrator, disabled student, revoked device, expired Auth session, ended admission, nonadmitted student, unverified student, banned student, missing/mismatched Auth session, and authenticated role without identity.
- All cursor/input contract errors, unchanged ordinary-student authoring denial, published assignment/link material invisibility/private detail denial, canary-free catalog output, no catalog audit/operation side effects, and existing private bucket/cover-only Storage policy boundaries.

Require a result column named **`phase2_catalog_report`** whose JSON value has `status="PASS"`, `passed=155`, `expected=155`, plus all 155 `{name,outcome:"PASS"}` entries. Absence of an exception, an empty result, a partial assertion list or a different count is not a pass. This document records the expected result, not a runtime result.

## Main execution method and cleanup

Run the entire `supabase/tests/phase2_catalog.sql` in one privileged connection with stop-on-error. The file includes BEGIN, local statement/lock timeouts, local role/JWT fixture switches, the exact-count report, ROLLBACK and a final read-only cleanup SELECT. Do not send setup, role switches or individual assertions as unrelated requests. Privileged reads use RESET ROLE; all catalog behavior is tested under authenticated/anonymous roles, not a bypass-RLS connection.

For a connector that returns only the last SELECT, submit through the suite's ROLLBACK to capture `phase2_catalog_report`, then run the trailing cleanup SELECT separately. Require zero in all **twelve** counts: users, Auth sessions, accounts, devices, application admissions, audit events, courses, course sessions, materials, material operations, canary payloads and reserved-prefix Storage objects. Do not remove rollback or commit fixtures to obtain output.

Fixture identities use **`f2c0e400-0000-4000-8000-`**: users 001–002, Auth sessions 101–102, courses 201–232, sessions 501–528 plus 531–533, metadata-only image token 801, and operation IDs 901–904. UUID 999 is an intentionally nonexistent cursor/identity target, not a new user. Generated device/material UUIDs belong to reserved users/parents and are covered by creator/parent/FK cleanup checks. Emails are `example.invalid`. Searchable fixture text uses reserved `CAT4 ` labels; a collision guard aborts if preexisting course fields use that namespace, rather than changing or hiding real content. Plain identity/course/session INSERT also fails on UUID collisions.

All Auth/account/device/session mutation predicates reference only the fictional reserved IDs. Course lifecycle and failed constraint probes also target fixed fixture IDs. The suite never mutates the owner account, disables real sessions, globally archives the catalog or deletes real data. Storage is inspected read-only: **no object rows, upload reservations, binary uploads or Storage deletions are created or executed**. Materials fixtures publish authoring state solely inside the rollback transaction and cannot open student delivery.

The full-catalog filter comparison intentionally tolerates existing academy content and reads the current authorized published catalog. Tests do not require the real catalog to be empty. Original rows/grants/policies remain unchanged after rollback. On error, ROLLBACK on the same persistent connection or disconnect before reuse; do not continue a failed transaction. Audit identity sequences can advance even when rows roll back; never reset them. External database trigger/webhook side effects, if configured, remain the executor's review responsibility.

After the catalog suite, run identity/content/cover/material suites as separate transactions. Existing scripts share temporary helper names; combining them in one uncommitted transaction is not supported. Main owns runtime results, fixture cleanup readbacks and live advisory review. This suite does not prove JWT gateway signature checks, real-device catalog UI, Storage binary enforcement, concurrent reorder behavior or production readiness.

## Static verification and remaining work

The suite author inspected the Agency Backend Architect guidance and full Supabase/Postgres skill instructions, current content/identity/cover/material contracts, and relevant primary documentation. Static review covers paired SQL quotes/parentheses, function/grant signatures, exact projection fields, assertion-name uniqueness/count arithmetic, fixture-only mutation predicates, and absence of Storage writes. No fresh dependencies were installed and no runtime PASS is claimed.

Next: main executes the rollback suite against the reported hosted version and verifies the exact report plus twelve zero cleanup counts; address any concrete failure through reviewed changes. The frozen migration must not be edited silently after deployment. Client consumers remain separately owned and must implement actor/query-bound response handling and accessible fallback/error/loading/empty states. No push of this follow-up work was performed; the earlier editor push `f79f359` does not approve new work.

References: [Supabase database functions](https://supabase.com/docs/guides/database/functions), [PostgreSQL literal string functions](https://www.postgresql.org/docs/current/functions-string.html). Skills informed invoker/grant boundaries, indexed keyset access and explicit privilege-versus-RLS checks; guidance inspection is not evidence of executed database tests.
