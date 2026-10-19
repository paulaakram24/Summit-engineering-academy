# Session materials contract — milestone 2.3

Date: 2026-10-19. Status: proposed implementation contract, documentation only. No migration, RPC, Storage policy, provider integration or device acceptance is implemented by this document. Ownership for this preparation task is this new file only; concurrent cover UI work and status files remain with main.

## 1. Authority and inspected baseline

`REQUIREMENTS_CORRECTIONS.md` takes precedence over omissions in `MASTER_BUILD_PROMPT.md`. The roadmap places descriptors in 2.3, discovery in 2.4, entitlements in phase 3, protected delivery in phase 4 and submissions/grading in phase 5. This contract deliberately stages those boundaries rather than treating a descriptor as a delivery grant.

Inspected local mirrors of deployed development migrations:

| Migration / evidence | Contract dependency |
| --- | --- |
| `20261016060804_phase1_identity.sql` | `private.account_access`, devices, admitted sessions, `private.is_active()`, private security events; three initially closed private buckets |
| `20261016110640_logout_before_registration.sql` | Ended-session tombstone prevents delayed device registration from restoring access |
| `20261018154932_phase2_content_core.sql` | `public.courses` and `public.course_sessions`, `private.is_admin()`, piaster prices, immutable session parent, lifecycle triggers and audit |
| `20261019015308_phase2_private_covers.sql` | Reservation-owned immutable objects, compare-and-swap attachment, irreversible retirement and cleanup tombstones |
| `docs/CONTENT_CONTRACT.md`, `docs/PHASE2_COVERS.md` | Recorded hosted content 130/130, identity 84/84 and cover 53/53 results; these are prior evidence, not tests rerun for this design |

The identity helper checks actual Auth session existence/expiry, confirmed nonanonymous user, account enablement, admitted active session and unrevoked device. The admin helper additionally reads the server-owned account role. Reuse these checks; neither Flutter visibility nor editable JWT user metadata authorizes anything.

Existing course/session metadata is readable by active students only when published, nondeleted and, for sessions, under a published nondeleted course. `courses.cover_path` is intentionally student-readable for cover rendering. That is an image-specific exception: material object paths and provider identifiers must never follow that pattern. Do not reuse the cover bucket, its read helper, its path field or its read policies for session materials.

`course-materials` currently permits PDF/JPEG/PNG up to 52,428,800 bytes and is private with no material policies. `assignment-submissions` and `payment-receipts` remain closed. There is no deployed materials/entitlements schema in the inspected migrations. No live database state was queried for this preparation.

## 2. Fixed scope and staged delivery

1. **2.3-A: admin descriptor foundation.** Multiple independently ordered video, PDF, file, link and assignment descriptors per session, with authoring, lifecycle, restore and audit. No blob upload, playback signing or student material access is required to complete this slice. Draft placeholders are valid and visibly unconfigured. Assignment authoring means instructions/resources, not student submissions or grades.
2. **2.3-B: admin asset preparation.** Add private asset reservations, quarantine/scanner callback and replacement/cleanup operations. Stage provider configuration for Cloudflare Stream only. Keep incomplete integrations explicitly unavailable; do not claim that a MIME check is a malware scan. This slice can follow A independently of payment decisions.
3. **2.4: student discovery projection.** Expose only an allowlisted descriptor projection under published parents, with locked indicators. Do not expose private payload tables or URLs. Discovery is not delivery; previews require a separate explicit server path.
4. **Phases 3/4: student delivery.** Open only after entitlement, current session/device, lifecycle, scan/readiness and resource permission checks pass. Before then every student material resolution, including guessed IDs, zero-price items and `is_free_preview=true` sessions, fails closed. No placeholder endpoint may issue a real capability.
5. **Phase 5: submissions and results.** Add private student-owned submissions, admin grading/feedback and student-only result reads with separate policies; do not overload instructor resource storage or descriptor state.

PDFs are always view-only. Paid learning materials have no offline library, prefetch or persistent media cache. Ordinary file descriptors do not imply downloads. Assignment resource downloads require an explicit resource-level administrator permission and later authorization at delivery time; they are the deliberate export exception, not a general paid-material download switch. An assignment PDF remains view-only even if a client requests download. Broader nonassignment file export rules stay a later decision; default deny satisfies the current no-offline boundary.

## 3. Proposed relational schema

Names below are proposed additions, not existing tables. Use expand-only migrations initially; do not rename `course_sessions`, alter existing session numbering uniqueness, change prices or backfill real content. UUIDs are application identities, never secrets or authorization capabilities.

### Descriptor table: `public.session_materials`

| Field | Type / rule |
| --- | --- |
| `id` | UUID primary key, server-generated |
| `session_id` | UUID, not null, FK `public.course_sessions(id)`, immutable, delete restricted |
| `kind` | Required text CHECK: `video`, `pdf`, `file`, `link`, `assignment`; immutable after create |
| `title` | Trimmed text, 1–160 characters |
| `summary` | Plain text, default empty, at most 10,000 characters; catalog-safe description only |
| `position` | Nonnegative integer; display order `(position,id)` |
| `status` | `draft` default, `published`, `archived` |
| `deleted_at` | Nullable timestamptz; nonnull requires archived status |
| `revision` | Positive bigint, starts at 1, incremented by server mutation |
| `created_by`, `created_at`, `updated_at` | Server-owned creator FK and timestamps, following existing content conventions |

There is no per-session singleton by kind and no fixed business count cap. Multiple PDFs, videos, assignments, links and files can coexist in one mixed ordered list. `session_number` stays on the parent session, not the material. Do not duplicate course ID or add a material price/free-access flag: parent relationship and later grants determine delivery.

Do not add arbitrary JSON metadata, paths, source filenames, provider IDs, targets, tokens, paid instructions or assignment answers to this table. `summary` is descriptive, not a place to paste protected links. Validation rejects URL/HTML embed fields and obvious locator input in summaries; author UI routes targets to private fields. Such validation cannot guarantee an administrator never manually types sensitive text, so label catalog-safe fields clearly and review the later student projection before enabling it.

### Protected payloads: private schema only

All tables below have RLS, explicit revocation of client table privileges and no student policies. They are excluded from exposed API schemas, Realtime publication and public search/exports. Use typed columns rather than an unrestricted payload bag.

| Table | Required contract |
| --- | --- |
| `private.material_payloads` | `material_id` PK/FK, one row per descriptor; protected `body_text` (assignment instructions or paid text, bounded to 10,000 chars), nullable HTTPS `target_url` for link kind only, nullable `current_asset_id`; per-kind validation enforced transactionally |
| `private.material_assets` | UUID PK; immutable `material_id` FK; provider `supabase_storage` or `cloudflare_stream`; private bucket/object key or Stream UID (exclusive by provider); server-observed MIME/bytes/hash where applicable; creator/timestamps; operational and scan states; immutable object version identity |
| `private.assignment_resources` | UUID PK; `material_id` referencing assignment kind; title 1–160 chars; nonnegative position; asset FK; `download_allowed=false`; revision/timestamps and soft-delete fields. Multiple resources per assignment; one owner material for each asset |
| `private.material_operations` | Actor + operation UUID unique; operation kind, input digest and safe result identity/revision for idempotent create/replacement retries; no credentials, URLs or file bodies |

Top-level video/PDF/file descriptors resolve through `current_asset_id`; link descriptors resolve only through `target_url`; assignment descriptors carry protected instructions plus zero or more resources. Assignment resources use the same private asset ledger, never the future student submissions bucket. No student submission/grade/answer table is created in A.

Enforce asset ownership using a composite FK from `(material_id,current_asset_id)` to the asset ledger's unique `(material_id,id)` pair; apply equivalent ownership checks to assignment resources. A file from another material/session cannot attach by UUID. Validate link/payload kind compatibility, PDF MIME and assignment-kind resource ownership in the mutation transaction, not with unsupported cross-table CHECK constraints. No client may change observed MIME/bytes/hash, scan results, creator, provider readiness or current asset reference directly.

Indexes: `(session_id,position,id) WHERE deleted_at IS NULL` for the ordinary list, `(session_id,position,id)` for include-deleted administration; FK indexes for creators and resource/asset owners; asset `(material_id,state,created_at,id)` for bounded cleanup; unique provider locator where populated. Reuse PK/unique indexes where they cover FK lookups. Paginate at 20 descriptors with a `(position,id)` keyset cursor and lifecycle filter; parent list changes require refresh. Page size is an operational bound, not a content cap.

### Publication and hierarchy

Content lifecycle: draft → published → archived, with explicit transitions back to draft for editing/republication. Soft-delete archives; restoring always returns draft with the same ID, order and private payload association. Clients cannot hard-delete any descriptor or asset ledger row.

Creation, edit, publication and restoration require nondeleted course and session parents. Parent draft/archived state does not prevent admin preparation. Parent deletion blocks child editing until restored, matching existing session behavior. Parent hiding does not rewrite child states or delete objects. Effective student visibility/delivery always checks the complete parent chain; restoring a parent to draft cannot expose its children.

A published descriptor must be structurally configured: link target present and validated, assignment instructions present, or a ready clean current asset for video/PDF/file. A allows draft placeholders for unintegrated media; there is no fake-ready marker. Publication remains admin authoring state while student delivery is closed. Parent session publication does not automatically publish draft descriptors. A failed material readiness check must not silently publish the item.

## 4. RLS, grants and RPC boundary

Enable RLS on every new table. Revoke table privileges from PUBLIC, anon and authenticated before granting only what is intended. In A, grant authenticated SELECT on `session_materials` with a SELECT policy requiring `(select private.is_admin())`; students, disabled accounts and nonadmitted/revoked/ended sessions see no rows. Do not grant authenticated INSERT/UPDATE/DELETE: all descriptor writes go through the validated authoring RPCs so protected fields, revisions and atomic audit cannot be bypassed. No direct client access to private tables.

Use narrowly granted public SECURITY INVOKER wrappers around restricted private helpers, consistent with the deployed cover convention. Private SECURITY DEFINER helpers are justified only for the cross-table authoring transaction; set empty `search_path`, fully qualify objects, check `private.is_admin()` inside every entry point and revoke default PUBLIC/anon EXECUTE. Grant only the individual helper signatures required by authenticated wrappers; private schema USAGE already exists and is not table authorization. Trusted worker functions get separate service-only grants and explicit worker authentication, never an admin bypass flag accepted from Flutter.

Proposed v1 RPC surface (typed parameters, reject unknown fields):

| Operation | Input / result / atomic rule |
| --- | --- |
| `create_session_material` | Session UUID, immutable kind, title/summary, position, operation UUID; create draft + appropriate empty private payload; return safe descriptor |
| `get_admin_material_detail` | Material UUID; active-admin-only private authoring projection; no signed URL or provider credential; private target can appear only in this explicit editor response |
| `update_session_material` | Material UUID, expected revision, editable descriptor fields and typed protected body/target parameters; validate per-kind allowlist; return descriptor with new revision |
| `transition_session_material` | Material UUID, expected revision, action `publish`, `archive`, `draft`, `soft_delete`, `restore`; readiness/parent validation and draft restore enforced server-side |
| `reorder_session_materials` | Session UUID and a bounded changed-item list of ID/expected-revision/position triples; reject duplicate/foreign/deleted IDs, lock and validate all, update all or none; return changed safe descriptors |
| `upsert_assignment_resource` | Assignment UUID, expected material revision, optional resource UUID, expected resource revision, title/position/download permission and operation UUID; private admin detail only; asset attach remains separate |
| `soft_delete_assignment_resource` / `restore_assignment_resource` | Owner assignment/resource IDs and expected revisions; preserve identity and permission history; restoring cannot make a retired asset deliverable |

Use `expected_revision` for all mutations of existing state. For each transaction lock the course, then session, then material and affected assets/resources in stable UUID order; recheck parent visibility and revision after locks. This serializes against existing parent lifecycle writes and avoids stale publication/reorder outcomes. Allow equal positions and use UUID tie-breaks; reorder uses sparse positions and bounded changed-row requests rather than imposing a session count limit. Configure an operational batch maximum before implementation and test it. Multi-request reorder is not one atomic operation; UI must present committed batches accurately.

Stable failures: SQLSTATE `42501` for admin/access denial, `22023` for invalid typed inputs, `40001` with `material_changed` for revision conflict; distinct safe `material_unavailable`, `parent_unavailable`, `material_not_ready` errors after admin authorization. Student-facing future resolution collapses unavailable/not-entitled/unknown ID to a nonenumerating denial. No error includes paths, URLs or SQL details. Clients refresh on revision conflicts; they do not silently overwrite.

Create/preparation use actor-scoped operation UUID plus input digest: retry with the same payload returns the original result, changed payload is rejected. Revision-changing retries must reconcile current state after an uncertain response; never blindly replay a destructive operation. Audit successful mutations once in the same transaction using `private.security_events`, with actor, entity/session IDs, action, state and changed-field names. Never serialize full rows/payloads or log targets, locators, filenames, tokens, scan bodies or student identity. Failure rolls back mutation and audit together.

Later 2.4 should expose an explicit allowlisted projection (`id`, `session_id`, `kind`, `title`, `summary`, `position`, published state, locked indication) with active-user and whole-parent-chain checks. Do not widen the base table to student SELECT or use `SELECT *` through a view. Prefer a SECURITY INVOKER projection when its underlying grants permit it; otherwise use a narrowly reviewed RPC with explicit checks and field construction, not a default definer view. Recent Materials/search/notifications must reuse that allowlist. No URLs in metadata, assignment resource details, counts of private submissions or provider readiness internals.

## 5. Asset, Storage and scan integration — subsequent slice

Do not open any existing closed bucket in A. For B reserve opaque immutable object paths server-side; preparing admin owns the reservation. No upsert, overwrite, move or client-chosen final key. Use the cover model's irreversible tombstones and expected-current-reference check, but define a materials-specific helper and policies. Do not copy the cover policy's student reads or its one-hour/five-reservation parameters without deciding upload-specific operational limits.

Operational asset states: `reserved → uploaded → quarantined → ready → attached → retired → cleaned`; invalid/abandoned/expired assets retire from preattachment states. Scan state is separate: `pending`, `clean`, `rejected`, `error`; it cannot be set by the app. For Stream, trusted provider processing/signed-playback configuration is an additional readiness check, not a claim that Cloudflare performs the application's malware scanning. Unimplemented validation remains pending and cannot attach/publish. Track failures privately, with safe admin UI reasons.

Storage INSERT requires an unexpired owned reservation, active admin, exact bucket/path/type/size constraints and no deleted parent. No Storage UPDATE policy. Quarantined objects have no general read/list/signed-URL permissions, including for the uploading admin; scanner access is trusted service-only. Preparation responses may contain a scoped admin upload destination, never a student descriptor. Do not return raw unscanned file preview bytes to a renderer.

The scanner integration receives asset UUID, immutable version/hash and trusted locator privately. Validate size, sniffed type and actual content; reject extension/MIME mismatch and active/unsupported formats. Callback verifies worker credentials, asset/hash/version and event identity, records scanner outcome atomically and rejects stale or replayed state changes. Retries use bounded backoff and a failed/pending queue; scanner outage fails closed. No manual client `clean=true` override. No URL fetching merely because an admin entered a link: validate HTTPS, disallow credentials/unsafe schemes, and avoid server-side fetching/SSRF. External link destination safety is not equivalent to scanning a stored file.

Use `course-materials` only under its current allowed PDF/JPEG/PNG/50 MiB limits until a separately reviewed type/size change. Do not add ZIP/office/executable/HTML/SVG support implicitly for generic `file` descriptors. A descriptor can remain draft without an accepted binary format. Quarantine can be a reserved private namespace in that bucket with zero client reads; a separate quarantine bucket is optional later infrastructure, not assumed provisioned. Never store video binaries there; Cloudflare Stream is selected.

Trusted attachment requires clean immutable bytes (and Stream readiness where relevant), ownership, live parents and expected current asset/revision; swapping and retiring the previous asset occur atomically. Retrying a committed attach returns its result; abandon cannot retire an already attached asset. Descriptor soft-delete retains its current asset for recoverable restore; explicit replacement/detachment retires the old asset permanently. Retired/cleaned assets cannot reattach, and a restored descriptor with a cleaned/missing asset must stay draft/unconfigured until a new asset is prepared.

Cleanup operates on bounded retired/unreferenced batches, rechecks all current descriptor/resource references, uses Storage API/provider deletion rather than SQL object-row deletion, confirms absence before `cleaned`, and retains tombstones. Late uploads at tombstoned paths are cleanup candidates again and never attachable. No automatic retention/purge schedule is invented here. Timeouts are uncertain outcomes: reconcile provider/object/ledger state before retry or cleanup. Before B implementation specify upload/scan/provider timeout budgets, retry bounds, reservation limits and signing/admin rate limits as operational configuration, distinct from entitlement expiry.

## 6. Future delivery gate and honest protection limits

A server resolver accepts only material/resource UUID plus requested action (`view`, `play`, `open_link`, `download_assignment_resource`). It never trusts a client URL/path, account role, price, purchase receipt, entitlement flag or clock. It verifies current Auth/admission/device state, active account, whole published/nondeleted parent chain, material/resource lifecycle, ready clean current asset and a valid server-owned grant. A course grant includes future sessions while valid; an individual session purchase does not create course enrollment. Bundle behavior and expiry rules belong to phase 3.

Only then may a trusted endpoint resolve private data and issue narrowly scoped short-lived playback/view/export capability. Cloudflare Stream must require signed playback and have public/download variants disabled as applicable; verify provider behavior before release. Preview handling is explicit and server-controlled, not `price=0` or a client flag. Exact capability TTL, revocation exposure window and entitlement duration/start/renewal remain later decisions; no numeric expiry is assumed.

For PDFs use an in-app viewer without download/share/print actions and no persistent cache. A signed PDF URL is a bearer capability, not a proof of view-only protection: a client receiving PDF bytes can save them. If stronger control is required, evaluate an authenticated page-rendering delivery service before phase 4 acceptance; rendered pixels can still be captured. Screenshots, recording, rooted devices and extraction cannot be completely prevented. Watermarks deter sharing but are not access control and must not put student identity into public metadata.

For paid learning materials disable offline saving, background prefetch, service-worker/media caches and OS export intents; clear temporary buffers/files on logout, access loss and view close, and request private/no-store responses where controlled. Audit third-party player/viewer caching before enabling delivery. These measures cannot revoke bytes already captured. Previously issued bearer capabilities may outlive a database revocation until their own validity ends; document/test the selected bound. Assignment export requires explicit permission on that exact non-PDF resource plus entitlement; a downloaded permitted assignment file cannot be recalled and must not be described as revocable/offline-protected.

External links are protected before resolution, but a destination opened outside the app can be copied and cannot inherit app entitlement enforcement. Do not use external links as a substitute for protected paid PDF/video hosting; unresolved destination protection keeps that item unavailable.

## 7. Exact acceptance checks and evidence required

These are implementation gates to execute later, not results of this documentation task.

| Check | Required observable result |
| --- | --- |
| A1 Multiplicity and pagination | One fixture session holds at least two of each of the five kinds; >20 mixed descriptors paginate without missing/duplicate IDs in an unchanged list; equal positions sort by UUID |
| A2 Admin authorization | Admitted active admin can author; anon lacks RPC EXECUTE; active student, forged user-metadata admin, disabled/banned/unverified account, expired/missing Auth session, ended admission and revoked device all fail reads/mutations |
| A3 Direct privilege denial | Student sees zero descriptor rows; authenticated direct writes fail even for admin; private payload/asset/resource/operation tables cannot be selected or changed via client API; hard-delete denied |
| A4 Invariants | Blank/oversized text, invalid kind/status/order, parent/kind/creator/ID mutation, cross-material attachment and invalid resource ownership fail; no partial descriptor/payload/audit remains |
| A5 Lifecycle | Delete archives; restore returns draft with same identity; deleted parent blocks edits; hidden parent prevents later student discovery/delivery; restoring parent alone exposes nothing |
| A6 Publication | Unconfigured video/PDF/file and missing link/assignment body cannot publish; valid configured assignment/link may publish as authoring state without opening student resolution |
| A7 Concurrency/idempotency | Two edits with same revision produce one success and one `40001/material_changed`; stale reorder batch changes no rows; foreign/duplicate IDs rejected; retried create with same operation UUID creates/audits once; changed retry payload rejected |
| A8 Privacy | Canary Stream UID, object path, target query token and assignment body appear only in authorized private editor detail, never descriptor SELECT/JSON, catalog/search/export/notifications, error text or audit; admin and future student serializers use field allowlists |
| A9 Delivery stays closed | Known/guessed material IDs, zero prices, preview flags and forged purchase claims yield no student bytes, link target, signed URL or playback token; material/submission/receipt bucket policies remain unchanged in A |
| A10 Audit and UI | Every successful mutation is atomically audited with safe fields; failed transaction leaves neither write nor event; UI distinguishes draft/unconfigured/locked/permission failures, refreshes conflicts and discards late data after access loss |
| B1 Upload/scan | Real binary wrong type/size, forged clean result, pending/rejected/error scan and wrong asset hash cannot attach/read/sign; duplicate callback is idempotent; scanner outage leaves unavailable state |
| B2 Asset races | Stale replacement cannot overwrite current asset; abandon after successful uncertain attach preserves it; cleanup cannot delete referenced assets; retired paths cannot upload/attach; late objects are relisted |
| B3 Provider/Storage integration | Actual Storage API upload/delete and provider callbacks/readiness verified separately from SQL metadata fixtures; no public material bucket/list/read path or default unsigned Stream playback |
| C1 Entitlement boundary | Session-only, valid course future-session, revoked/expired/unknown grants, invalid devices and simultaneous-login cases resolve exactly as phase 3 policy; deny before minting capability |
| C2 PDF/offline/export | PDF has no save/share/print UI or persistent cached file; no offline paid library; PDF download denied even on assignment; unpermitted assignment export denied; explicit non-PDF resource export works only for authorized current user |
| C3 Residual capability exposure | Measure and record selected URL/token expiry and behavior after revoke, logout and parent archival; no claim of instantaneous recall or screenshot prevention |

Database regression must run identity, content and cover suites plus a new materials suite with named expected totals, rollback fixture isolation and zero reserved-fixture cleanup readbacks. Update their current closed-bucket assertions only when B introduces narrowly named reviewed material policies; do not weaken them to accept arbitrary policies. Include real concurrent connections for race claims; sequential SQL is insufficient. SQL metadata fixtures do not establish binary scanning, Storage HTTP enforcement or gateway JWT verification.

Flutter repository/model/widget checks cover each kind, server-owned field allowlists, mixed ordering, pagination, restore-to-draft, conflict handling, cancellation and access loss. Verify via signed-in API and device flows later using explicitly authorized temporary content; main owns those steps. This task does not touch the phone or mark roadmap gates complete.

## 8. Recorded later decisions — no interruption required

- Owner confirmed on 2026-10-19: access starts on admin approval, with no automatic expiry while content remains available, until authorized removal. Refund behavior, bundles and distribution billing policy remain open at roadmap 3.1. Keep InstaPay/Vodafone Cash destination details pending until 3.2. Technical Auth/capability expiry is separate from business entitlement duration.
- Confirm supported non-PDF assignment resource formats and any broader explicit attachment export policy. Existing upload MIME/size restrictions remain authoritative until reviewed changes.
- Choose scanner service, callback credentials, supported content validation, operational limits, quarantine retention and purge policy before B uploads become usable. Absence blocks asset readiness, not descriptor authoring.
- Confirm Cloudflare account availability/configuration and signed-playback enforcement before provider integration; no alternate provider is silently selected.
- Choose PDF renderer/protection level, watermark presentation, temporary-file behavior and capability TTL before phase 4 delivery. Describe extraction and external-link limitations honestly.
- Define assignment deadlines, submission types/limits, grading scale and result visibility in phase 5; no placeholder payment/expiry/grading rules are inferred for A.

Owner is unavailable until 10:45 Cairo; questions are recorded here for later review, not sent or asked during preparation.

## 9. Next implementation order and review boundary

Implement A as a small schema/RLS/RPC change with its rollback-based database suite, then Flutter admin descriptor models/repository/editor and focused tests. Review allowlisted outputs and existing-suite compatibility before any development deployment. Keep B asset upload/scanning/provider work a separate reviewed increment, followed by discovery and entitlement-gated delivery in their roadmap phases. Reverting A UI must leave schema/data intact; disable RPC entry grants or UI entry on a defect rather than dropping authored content. No existing cover or identity behavior needs changing for A.

Preparation verification: read the requirements, roadmap, Agency Backend Architect guidance, Supabase and Postgres skill instructions and the local identity/content/cover migrations; reviewed this document for scope/privacy/gate consistency. No backend tests, migration application, server changes, dependency changes, phone interaction or push were performed. Main retains responsibility for updating shared project-management files when implementation occurs.

Provider references checked for the design: [Supabase RLS/grants](https://supabase.com/docs/guides/database/postgres/row-level-security), [Storage access control](https://supabase.com/docs/guides/storage/security/access-control), [Cloudflare signed playback](https://developers.cloudflare.com/stream/viewing-videos/securing-your-stream/). The [Supabase changelog](https://supabase.com/changelog.md) was retrieved; recheck relevant changes when implementing. Guidance favors explicit grants plus RLS, private privileged helpers, indexed ownership lookups and partial indexes for active lists; it does not certify this proposed implementation.
