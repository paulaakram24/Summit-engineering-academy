# Phase 2.3-A — admin session descriptors

2026-10-19. **Admin-only schema deployed to development and rollback suite passed 163/163.** Main reviewed the additive migration and deployed through the authorized Supabase connector as version 20261019154009, then parsed the complete named PASS report. Identity 84/84, content 130/130 and covers 53/53 also passed afterward (430 assertions total). The CLI was not authenticated; no CLI credentials were requested. No atomic predeployment schema-plus-suite preflight was run, so these are postdeployment development results, not preflight evidence. No media delivery or student access is enabled. UI/physical material acceptance remains open.

Files:

- `supabase/migrations/20261019154009_phase2_admin_materials.sql`
- `supabase/tests/phase2_materials.sql`
- This document.

The migration was initially created using `supabase migration new phase2_admin_materials` after reading CLI help; its local timestamp was subsequently aligned to the actual hosted connector version 20261019154009. Prerequisites are both identity migrations, content core `20261018154932` and private-cover baseline `20261019015308`. CI now includes the rollback material suite; no hosted CI run is claimed for unpushed changes.

Independent cleanup readback found all eight reserved-fixture counts zero, plus zero material rows, payloads and operation records. No owner-account mutations or real Storage deletions occur in this suite. Cover binary acceptance is recorded separately.

Postdeployment advisors: seven intentional private-schema RLS/no-policy notices, the existing [disabled leaked-password protection warning](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection), unused development indexes and one [composite foreign-key index notice](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys). The latter is material_payloads(material_id,kind); its existing unique material_id primary-key index already bounds parent lookup to at most one row. No redundant composite index was added solely to silence the notice; measure a real workload before changing indexes. No paid Auth setting or security policy was changed to suppress findings.

## Implemented boundary

`public.session_materials` holds only ID, immutable session/kind, title/summary, position, lifecycle/deletion state, revision and server identity/timestamps. The five kinds are video, PDF, file, link and assignment, with unlimited multiplicity by kind. `(position,id)` supplies deterministic ordering, including ties. Indexed ordinary/include-deleted queries can paginate at 20 without a business content cap. **Bulk reorder RPC is deferred**; update position using the same revision CAS as other edits. Multiple position edits are separate transactions, not one atomic reorder.

Authenticated callers receive base SELECT privilege, but the only RLS policy requires the existing `private.is_admin()` helper. Students see no descriptors, including published items under published/free-preview/zero-price parents. No client has base INSERT/UPDATE/DELETE or direct private table access. Every callable privileged helper rechecks the server-owned administrator role and active admitted Auth/device/session state. Public wrappers are SECURITY INVOKER, private transaction/detail helpers are SECURITY DEFINER with empty search paths, and default PUBLIC/anonymous execution is revoked. Owner-only serialization/locking/trigger helpers have no client execution grants.

`private.material_payloads` holds protected assignment body text and link URL; its composite FK ties payload kind to descriptor kind. `private.material_operations` holds actor-scoped operation UUIDs, argument hashes and safe descriptor snapshots. Both private tables have RLS with no client policies or grants. No arbitrary JSON payload, locator, provider UID, file path or URL is added to the base metadata table. The admin-only detail response explicitly separates descriptor from protected body/target and reads both in one statement snapshot.

Titles must trim to 1–160 characters, summary/body are bounded to 10,000 characters, position is a nonnegative integer, and target is at most 4,096 characters. Body is allowed only on assignments and target only on links. Targets use lowercase `https://`, an ASCII host with optional numeric port and path/query/fragment, and reject credentials, raw whitespace/control characters, backslashes and angle brackets. This is structural validation only: no URL fetch, destination reputation check or protected-hosting guarantee is implemented. Encoded targets still require delivery-time review before a future external launch path.

Title/summary reject obvious HTTP(S)/www URLs and HTML embeds. This is a conservative catalog-field guard, not a general detector for manually typed secrets/provider identifiers. There is currently no student metadata projection; any later discovery/search/export implementation must independently use an explicit safe allowlist and review authored descriptions. Nothing in this slice authorizes paid content delivery.

## RPC contract

All parameters are required, including explicit empty text/nulls; there are no ambiguous defaulted overloads. UUID arguments are PostgreSQL UUIDs, revisions bigint, positions integer. Mutation return values are safe descriptor JSON, never protected body/target.

| Public function | Parameters in order |
| --- | --- |
| `create_session_material` | `p_session_id`, `p_kind`, `p_title`, `p_summary`, `p_position`, `p_body_text`, `p_target_url`, `p_operation_id` |
| `get_admin_material_detail` | `p_material_id` |
| `update_session_material` | `p_material_id`, `p_expected_revision`, `p_title`, `p_summary`, `p_position`, `p_status`, `p_body_text`, `p_target_url`, `p_operation_id` |
| `delete_session_material` | `p_material_id`, `p_expected_revision`, `p_operation_id` |
| `restore_session_material` | `p_material_id`, `p_expected_revision`, `p_operation_id` |

Create always produces draft revision 1. For placeholders supply body `''` and target NULL. Link can have a private target or remain unconfigured; assignment can have a protected body or remain unconfigured. Update is a complete replacement of the editable field set, not a JSON merge. It cannot reassign session/kind, identity, creator or creation time. A trigger reinforces immutable identity and exactly-one revision increments; server code stamps update time.

Update can move among draft/published/archived states. A link publishes only with a valid target; assignment only with a nonempty trimmed body. Video/PDF/file descriptors cannot publish in A because there is no asset readiness model; they remain useful draft/archived placeholders. Published link/assignment is **admin authoring state only**, not student access.

Delete is soft deletion: archived plus deletion timestamp and revision increment. Restore preserves identity/parent/kind/payload and returns to draft. Editing/deleting an already deleted material, or restoring a live material, fails unless it is an exact operation retry. There is no permanent-delete RPC.

All mutations, including cached retries, require nondeleted course and session parents. Draft/archived parents permit preparation. Parent deletion does not rewrite child state, and restoring a parent does not publish or change material revisions. Admin detail/base reads remain available for recovery even when parents/materials are deleted; that read exception is intentional and grants no write/delivery path.

## Concurrency, retries and audit

Every mutation requires a fresh operation UUID for new intent. The private operation ledger is unique on `(actor_id,operation_id)`. An INSERT conflict followed by row lock serializes same-operation requests; a SHA-256 digest of the complete typed request rejects a changed payload or cross-action reuse. No cleartext protected request is stored in the ledger. There is no retention/purge job in this slice.

Client follow-up: every retained mutation request also requires the originating authenticated actorId, preserved with its operation ID on exact retry. It is not inferred from descriptor.createdBy because administrators may edit other administrators' authored materials. The repository requires a nonexpired live Auth session matching that actor, pins the RPC Authorization header to the checked session without changing shared client headers, and rechecks identity after response/timeout before returning. Signed-out/cross-actor retries fail closed; a transmitted mutation may already have committed, so never create a replacement operation automatically. The actor binding is a client correctness safeguard; server role/device/admission checks remain authoritative. The material UI must clear retained requests and protected payloads when access closes and refetch before further editing.

Lock order is operation, course, session, material. Parent rows are locked and deletion rechecked before mutation; update/delete/restore then compare expected material revision while holding its lock. A stale revision raises `40001 / material_changed` without changing descriptor, payload, operation ledger or audit. Main must still test actual parallel connections before claiming race behavior; this suite checks sequential stale-revision outcomes only.

**An exact idempotent retry returns the original operation snapshot. It may describe an earlier revision or an item that has since been edited/deleted. Clients must refetch detail/list after a retry, before rendering current lifecycle controls or editing again.** Replaying an old create/update does not run it again and cannot resurrect a deleted item. A now-invalid admin session or deleted parent still blocks the cached response. Client use of the old snapshot is not permission to overwrite current state.

Each successful new mutation writes exactly one `material_create`, `material_update`, `material_delete` or `material_restore` event in `private.security_events`, atomically with descriptor/payload/operation state. Audit includes actor/subject, entity/material/session IDs, status, deleted indicator and revision. It does not serialize full rows, bodies, URLs, filenames, tokens or hashes. Exact retries add no events. Failure rolls back the operation reservation and any in-flight mutation/audit.

The descriptor serializer is STABLE, not IMMUTABLE: JSON serialization of timestamptz values depends on session timezone. Persisted operation snapshots preserve their original serialization; clients should parse timestamps as instants, not compare newly serialized JSON text across timezones.

Stable errors:

| SQLSTATE / message | Meaning |
| --- | --- |
| `42501 / admin_required` | No currently authorized admitted administrator |
| `42501 / parent_unavailable` | Course/session missing or deleted |
| `42501 / material_unavailable` | Unknown item or invalid deleted/live action |
| `40001 / material_changed` | Expected revision is stale; refresh and reconcile |
| `22023 / material_operation_reused` | Same actor/operation ID with different request |
| `22023 / invalid_material_input` | Invalid kind/status/fields/revision/operation structure |
| `22023 / invalid_material_payload` | Wrong payload kind, invalid/oversized target |
| `22023 / material_not_ready` | Unsupported/unconfigured publication |

Trigger failures use `22023 / material_identity_immutable` or `material_revision_invalid`. They are defense in depth, not intended client edit paths. PostgreSQL function/table permission errors remain possible for anonymous/direct-DML attempts. Do not display raw database messages or protected editor payloads in telemetry.

## Regression suite and exact report

The suite contains **163 expected assertions: 100 explicitly named checks plus seven checks for each of nine authenticated denial scenarios**. Helper assertions use SECURITY INVOKER, `INTO STRICT` booleans, exact SQLSTATE/message comparisons and unique names. Helper failures are outside the caught tested statement, preventing false passes. An explicit count guard throws unless exactly 163 result rows exist.

Coverage includes five of every kind in one session, 20+5 keyset pages with tied positions, create/update/delete/restore idempotency, changed operation input, stale CAS, old create/update replay after deletion without resurrection, private detail/projection separation, canary-free audit/results, invalid fields/URLs, placeholder publication denial, configured link/assignment states, lifecycle/parent guards, actor-isolated operation IDs, direct-client DML/private table denial and privileged identity-trigger checks. The deliberate `mutate_then_fail` test verifies subtransaction rollback of descriptor/payload/operation/audit after the mutation function has returned.

The denial matrix covers forged-role student, disabled admin, revoked device, expired Auth session, ended admission, nonadmitted account, unverified account, banned account and missing/mismatched Auth session. Each verifies base invisibility, all five RPCs and cached-create denial. Anonymous base reads and all five public RPC execution attempts are separately denied. Existing bucket privacy and the current cover-only Storage-policy allowlist are asserted; existing suites/CI were not edited.

Main should execute the suite on one privileged connection as one complete transaction with stop-on-error. Require this named JSON result immediately before rollback:

```json
{"phase2_materials_report":{"status":"PASS","passed":163,"expected":163,"tests":["163 uniquely named PASS outcomes"]}}
```

The actual SQL column is `phase2_materials_report`; its `tests` value is an array of `{name,outcome}` objects. The example abbreviates that array. An absent report, empty result, exception or mismatched count is not a pass. No runtime PASS is claimed by this document.

For preflight, main can combine one outer BEGIN, the migration body, and the suite after its opening BEGIN through its ROLLBACK. This tests migration plus fixtures atomically without retaining schema. The trailing cleanup query references only preexisting tables, so it also works after such a schema rollback. If the executor only returns the final SELECT, submit through ROLLBACK to capture the report, then run the trailing read-only cleanup query separately. Never remove rollback or commit fixtures to obtain output.

Fixture UUIDs use reserved prefix **`f2c0e300-0000-4000-8000-`**: users 001–003, Auth sessions 101–103, course 201, course session 301 and deliberate aborted operation 901; 999 is a nonexistent test target. Emails use `example.invalid`. Devices/materials use generated UUIDs tied to the reserved creators/parents. All fixture Auth/account/device updates select only those fictional IDs. Plain INSERT collision-fails; there is no identity upsert or owner cleanup.

Require zero in every trailing cleanup count: users, Auth sessions, accounts, devices, admissions, audit events, courses and course sessions. After a deployed-suite rollback main may additionally check the new tables by reserved creators/actors/parent; do not use these queries after a migration preflight rollback where those tables no longer exist:

```sql
select
 (select count(*) from public.session_materials
   where created_by::text like 'f2c0e300-%'
      or session_id='f2c0e300-0000-4000-8000-000000000301') as materials_remaining,
 (select count(*) from private.material_operations
   where actor_id::text like 'f2c0e300-%') as operations_remaining,
 (select count(*) from private.material_payloads
   where body_text like 'CANARY_BODY_%' or body_text='CANARY_ATOMIC'
      or target_url like 'https://example.invalid/%CANARY_%') as canary_payloads_remaining;
```

The new payload table has a restrictive FK to materials and materials to the fixed session, so rollback/zero parent and creator counts plus these extra readbacks cover generated fixture identities. If execution errors in a persistent connection, ROLLBACK on that same connection or disconnect before reuse. Audit identity sequences may advance despite rollback; never reset them. No Storage objects are inserted or deleted.

Run existing identity/content/cover suites independently after preflight; their temporary helper names may overlap, so do not combine the suites in one uncommitted transaction. Main owns advisory review and cleanup evidence. SQL JWT claims bypass gateway signature verification and do not establish signed-in HTTP behavior, binary upload enforcement, real concurrency, physical acceptance or production readiness.

## Static review, remaining gates and deferred decisions

Later editor checkpoint: 2.3.3 is now implemented and administrator-debug accepted on Huawei with synthetic assignment/link/video-placeholder persistence and recoverable lifecycle. Main passed 355 app tests and configured Android build; see docs/ADMIN_MATERIAL_EDITOR.md and docs/PHASE2_DEVICE_ACCEPTANCE.md. This supersedes the historical editor-open statement below, but does not complete assets/student delivery. No backend schema changed for the UI; the earlier 430 database assertions were not rerun merely for this editor. Approved foundation 5fa6d4a passed both remote workflows; later UI changes remain unpushed.

The initial static inspection checked SQL structure, grant signatures/search paths, assertion counts, fixture-only mutations, output/audit allowlists and operation totals. Subsequent main PostgreSQL execution and cleanup results are recorded at the top of this document; neither pass is a full security scan. No new parser/runtime dependency was installed. Main's STABLE serialization and snapshot replay corrections are incorporated.

Development deployment, exact report/cleanup readbacks, existing-suite regression and advisor review are now recorded above; atomic predeployment schema preflight was not run. Flutter models/repository/tests are a separate accepted slice: 105 focused tests, all 310 app tests, clean analysis/formatting and configured Android rebuild (4.1s) passed after the actor-bound retry correction. Independent focused review found no remaining concrete actor-switch/token-pinning regression; this is not a full security audit. Editor integration remains open. Recovery from a discovered defect should close new entry grants/UI rather than drop authored data; preserve existing identity/cover behavior.

Explicitly deferred: bulk reorder, assignment resources/submissions/grading, assets/uploads, quarantine/scanner, Cloudflare Stream integration, student descriptor reads/search, all delivery/signing, entitlements and payment processing. PDF view-only, no offline paid materials and explicit non-PDF assignment-resource export remain future delivery invariants; this slice issues no bytes or URL capabilities. Bundles, refunds, payment destinations and operational upload/scanner limits remain decisions for their owning milestones. No invented values or owner interruption are required to review this foundation.

Owner clarification received during implementation: access starts at administrator payment approval, has no automatic expiry, and continues until the administrator/instructor removes the session. Future entitlement work must follow the current `REQUIREMENTS_CORRECTIONS.md`; the earlier design's pending-expiry questions are superseded and main owns its reconciliation. Lost-device recovery requires administrator identity verification, revocation of only the lost device and release of that installation's admission so login can proceed; this is a later identity/recovery change, not a global action on other devices. No entitlement or device-recovery behavior is changed in this migration, and delivery remains closed.

Supabase/Postgres guidance informed separate grants/RLS, restricted definer helpers, indexed parent access, partial active-list indexes and short database-only lock scopes. References: [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security), [database functions](https://supabase.com/docs/guides/database/functions). Guidance review is not evidence of runtime verification.
