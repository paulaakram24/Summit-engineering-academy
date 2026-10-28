# Material upload quarantine cleanup — implementation design

Status: design only, 2026-10-23. This document creates no schema, endpoint, policy, worker, schedule or deletion capability. It authorizes no deletion. Any implementation requires a separate reviewed additive migration and service/client change; deployed migrations must not be edited.

## Basis and scope

Read alongside [MATERIAL_FILE_UPLOADS.md](MATERIAL_FILE_UPLOADS.md) and `supabase/migrations/20261023112810_phase2_material_file_uploads.sql`. The upload document records a deployed quarantine staging checkpoint; those operational results are supplied evidence, not a new verification performed for this design. Agency Backend Architect guidance informs the irreversible lifecycle, explicit contracts, lock order and recovery requirements below.

The existing ledger has immutable identity/request fields, restrictive parent/user references, and only `reserved` and `uploaded` states. Its trigger rejects deletion and all updates except reservation completion. Storage permits an admitted administrator to INSERT at the exact owned, unexpired reservation path. No client object read/update/delete policy exists. Completion checks observed MIME/size metadata, not bytes or cleanliness.

This sidecar concerns only `material-upload-quarantine`. Existing `course-materials`, cover, receipt and submission buckets retain their current settings and access boundaries. No bucket emptying, prefix deletion, wildcard removal, bucket deletion, relocation or overwrite belongs in this workflow. Delete one server-resolved asset key per explicit confirmation.

Supabase treats Storage metadata tables as read-only to application operations: inspect metadata when necessary, but perform real object removal through the Storage API. Never issue SQL DELETE against `storage.objects`, delete bucket rows, or use metadata manipulation to simulate deletion. Object removal is irreversible; retaining a ledger/tombstone does not restore removed bytes. References supplied by main's current documentation lookup: [Storage schema/design](https://supabase.com/docs/guides/storage/schema/design), [Deleting objects](https://supabase.com/docs/guides/storage/management/delete-objects).

No student access, preview/download URL, scanning verdict, clean/ready state, attachment, publication or delivery is introduced. Owner roles, receiving data, account admission, devices and sessions remain unchanged. Expired authorization is handled through ordinary authentication, never by resetting owner access.

Main reports that the native synthetic fixture was selected/cancelled only, with no cloud write. Picker cancellation must not create a cleanup request or be treated as an uploaded-object test. This design neither uploads that fixture nor deletes owner material.

## Initial eligibility and explicit confirmation

The first implementation should support abandoned or expired **reserved** assets only, including a reservation whose transfer/completion response was lost. Expiry makes an asset a review candidate; it is not permission to delete. Do not infer user abandonment from a timeout, failed RPC, missing local request, material revision drift, parent archival/deletion, or an empty recent-history page.

Historical `uploaded` assets remain retained private history in the initial increment. They are never selected automatically by age or parent lifecycle. A future discard feature for such assets requires a separately reviewed contract and explicit per-asset confirmation. There is no automatic retention/deletion period in this design.

Before any irreversible retirement or removal, an admitted original uploader must inspect a private candidate and explicitly confirm its asset ID and material association. The confirmation explains that removal cannot be undone, that a transfer may have succeeded despite a lost response, and that uploaded history is retained. The UI sends an opaque asset ID and one operation UUID, never a caller-selected bucket/path. Selecting a candidate, refreshing status and cancelling confirmation cause no mutation.

Candidates whose original uploader is disabled, demoted, unavailable or no longer admitted remain retained. Cross-administrator disposal and operator recovery are deferred choices, not an implicit authority granted to every administrator. Real owner uploads require the owner's explicit per-asset confirmation even when expired. There is no blanket cleanup consent.

Use a dedicated private candidate query, initially limited to 20 entries per page, ordered by `(created_at, asset_id)` with an opaque validated cursor. The ordinary last-20 upload history is insufficient to recover older/lost reservations. Return only owned candidate metadata needed for confirmation: asset/material IDs, declared filename/type/size, reservation timestamps, historical upload state and cleanup status. Do not expose paths, receiver data, tokens, hashes, bytes or other actors' candidates. A metadata-only candidate query is not permission to remove bytes.

## Proposed durable records and states

Keep the upload ledger and its two-state public projection unchanged. Represent disposal in separate private records rather than weakening the upload identity trigger or presenting `cleaned` as an upload validation state. Names below describe proposed contracts, not existing schema.

| Record | Required invariant |
| --- | --- |
| Retirement tombstone | One per asset; immutable asset, uploader, material/session/course association, exact bucket/key identity, initiating actor/operation, reason code and server retirement time. No update, deletion, reversal, retargeting or reattachment. |
| Cleanup operation | Actor/operation UUID unique; canonical hash of typed asset/reason/confirmation inputs. Reused operation with different inputs fails. Retried identical input returns the same operation, subject to current authorization. |
| Cleanup progress | References the tombstone; versioned monotonic progress and server timestamps. Worker claims have a bounded lease and fencing generation. No identity changes. |
| Attempt evidence | Append-only request/attempt IDs, fencing generation, timestamps, stable outcome codes and absence/drain observations. Do not store signed capabilities, raw provider errors, filenames or payloads in audit events. |

Proposed progress: `waiting_for_drain` → `eligible_for_remove` → `remove_pending` → `absence_observed` → `removed`. Failures leave the last durable nonterminal state plus an attempt outcome. `removed` is allowed only after the drain/reference/absence gates below; it means verified removal for this retired key, not a validation result. Reappearing objects trigger an incident/reconciliation record and retained quarantine, never identity reuse or silent resurrection.

Retirement is irreversible even if a later API call fails. Preserve the original upload ledger, operation history, tombstone and minimal cleanup evidence. Do not delete historical `uploaded` rows, rewrite their state to `reserved`, modify material descriptor revisions, or remove parent/user foreign keys to ease cleanup. Data minimization and tombstone retention duration require a later reviewed policy; indefinite minimal tombstone retention is the safe implementation default, not a decision to retain all personal metadata forever.

## Required database integration before activation

Adding a sidecar table alone is insufficient. A future additive migration must make prepare replay, Storage INSERT authorization, completion and the reservation-to-uploaded guard reject any asset with a retirement tombstone. Existing exact-input replay must not return a retired reservation as a usable upload capability. Existing safe history may still report its original state; new cleanup metadata must explain retirement separately without changing the frozen six-field upload projection. Older clients receive a stable unavailable response for retired mutation attempts.

The permanent tombstone must prevent a new writer from reusing the key even after Storage removal. New reservations always receive a new asset UUID/key. The ledger retains its unique actor/operation and key constraints. No direct client/service grants to the private sidecar or ledger are needed; any narrow service entry point must revalidate the complete contract.

For a confirmed retirement transaction, use the existing ordering: account/admission serialization → course → session → material → upload asset → cleanup operation/progress. Recheck authorization after waiting on locks. Lock parent rows even if archived or soft-deleted; ordinary `lock_material_parent` rejects deleted parents and cannot be reused unchanged for this purpose. Missing/inconsistent lineage fails closed. Cleanup cannot restore/edit parents as a workaround.

Under these locks, resolve immutable lineage, verify original uploader and `reserved` state, compare the reviewed asset snapshot, enforce references/holds, insert the unique operation/tombstone/progress and write an IDs-only audit event atomically. Exact operation replay returns reconciliation status; a different operation for the same retired asset must not create a second tombstone. Audit failure rolls back retirement and creates no permission to delete.

Completion and retirement must serialize on the same asset lock and consult the tombstone before changing state. If completion wins, the asset is historical `uploaded` and initial cleanup rejects it. If retirement wins, completion fails and the object remains quarantined for cleanup. Never allow both a successful initial cleanup retirement and a new accepted completion for that asset.

## References and recovery holds

The ledger's own identity/history foreign keys are intentional provenance, not usage references to erase. Cleanup must check every actual consumer reference and retention hold before retirement, before issuing removal and before recording final success. A soft-deleted or archived parent alone is not evidence of unreferenced bytes; recoverable parent deletion must preserve assets unless the asset is independently confirmed disposable.

Today no scan/attachment/delivery consumer reference is introduced by the upload migration. Implementation must inventory the then-current schema instead of assuming that remains true. Unknown reference surfaces or a hold block removal. A future attachment/reference writer must acquire the same asset lock, reject tombstones and register its reference before commit. Otherwise a last-minute reference check has a race and cleanup cannot be enabled alongside that writer.

Do not hold database locks or transactions open across Storage HTTP calls. The committed irreversible tombstone supplies the durable reference/write barrier between transactions. Immediately before deletion, a short transaction rechecks the same key, eligible progress version, fencing generation, current initiating authorization and reference/hold inventory. A capability for that single operation is not a general-purpose delete endpoint.

## In-flight writes and expiry: required drain proof

The current client timeout is not a server cancellation guarantee. Reservation expiry and retirement stop future authorized requests once observed; they do not prove that a request authorized earlier has stopped transferring or committing. SQL metadata absence can occur before an in-flight write becomes visible. Two empty reads, waiting an arbitrary hour, or a successful DELETE response alone cannot prove the key will stay absent.

Physical removal must remain disabled until the implementation establishes one of these reviewed mechanisms:

1. A provider-verified upper bound covering authorization-to-final-write duration for every permitted upload path, plus transaction/clock margins. Compute a server drain deadline after the retirement barrier and, for this initial design, no earlier than original reservation expiry plus that bound. Verify visibility semantics and the final authorization/commit path as part of acceptance. Client-only timeout settings do not supply the bound.
2. An enforceable server-side upload admission/lease barrier that stops new starts and proves all earlier writers completed or were terminated. A database flag that merely denies later INSERT checks is insufficient unless the entire binary-write lifecycle honors it.

The current direct Storage flow has no demonstrated drain mechanism in the evidence reviewed here. Record `waiting_for_drain`; retain bytes and show pending status until one is verified. Do not invent a retention period as a substitute. A broader upload-gateway redesign, resumable uploads, signed uploads or provider-side cancellation support would need separate scope and verification.

After drain proof, recheck metadata/reference state. A missing object may advance through verified absence without a DELETE request, but only after the same tombstone, authorization, drain and reference gates. Existing objects with mismatched metadata are still quarantined; mismatch is not grounds for attachment or automatic removal. For explicitly confirmed disposable reservations, exact immutable key binding is the deletion identity, not a filename or claimed MIME type.

## Storage API orchestration and failure recovery

Prefer a small trusted server handler for the explicit operation. It checks ordinary caller JWT/admission and original-uploader ownership, then resolves the single bucket/key from the tombstone. Storage credentials remain server-side. Do not add authenticated object SELECT/download privileges merely to make a client removal call work. Keep the existing client INSERT-only boundary; do not add broad client DELETE policies. The handler must not accept arbitrary keys, bucket names, arrays or prefix operations.

If the platform only offers a broadly privileged server credential, isolate it inside this handler and enforce the operation/key/reference contract before every call; role bypass is not authorization. Credential placement, available least-privilege capability and authenticated internal RPC grants are implementation gates still to resolve. Do not grant service-role access to unrelated private tables or alter owner roles.

Proposed explicit interfaces:

| Operation | Input and behavior |
| --- | --- |
| List candidates | Bounded cursor; metadata only, no mutation. Include old reserved entries outside recent history. |
| Confirm retirement | Asset ID, expected immutable snapshot/version, reason enum, operation UUID and per-asset confirmation; one transaction creates irreversible tombstone and audit. |
| Run cleanup attempt | Existing cleanup operation ID and expected progress version; reauthorize, validate drain/references, claim fenced attempt, call Storage API for its one key, reconcile. No implicit retirement. |
| Get cleanup status | Operation ID; return asset/operation IDs, historical upload state, progress version/state, stable pending/error code and timestamps. No paths or deletion capability. |

All names/signatures are provisional. Schema-bound functions need empty search paths, explicit grants/revokes, private RLS, input bounds and current server-controlled admission checks. Candidate/status queries must not reveal another actor's operation. Expired/ended/revoked sessions fail uniformly; ordinary reauthentication permits explicit reconciliation without changing account records.

Use a proposed 30-second HTTP request budget and one key/attempt; confirm platform limits during implementation. Timeout is an uncertain outcome. Return pending with the operation ID; never report success from an empty/failed response. Do not automatically retry destructive calls on the client. A subsequent explicit attempt first reconciles current state and reference/drain gates before repeating removal of the identical retired key.

Persist `remove_pending` before the external call. After API success, verify the documented removal semantics and an authoritative absence observation in a separate transaction before finalizing. A 404/no-row result can mean already absent only if the service had authority to observe that exact key; denied access, network errors and partial/listing responses are not absence. Metadata absence alone is not evidence that orphaned bytes were removed if the provider does not guarantee that correspondence.

If deletion succeeds but the final database/audit commit fails, leave the tombstone and pending attempt; later reconciliation can record absence without inventing a second deletion result. If API removal fails, preserve the tombstone and retryable pending state. No rollback can recover bytes after removal. Disable new attempts if implementation rollback is necessary, but preserve tombstones and write/reference barriers; restoring old upload functions that ignore tombstones is unsafe.

Concurrent callers claim progress with compare-and-swap and a generation fence. Only the current generation may publish a result. A lease expiring does not cancel a Storage request: takeover reconciles and observes the same exact key; a stale handler may not finalize another generation. Because retirement/reference exclusion and drain are permanent preconditions, any duplicate in-flight removal is confined to the same disposable key. Exactly-once HTTP execution is not promised; accepted retirement and finalization audits are emitted once, attempts have distinct IDs.

No scheduled sweep is included. Process one explicit asset at a time and expose pending/error outcomes. Operational metrics should count retained reserved/uploaded assets, declared bytes (clearly estimates), drain-pending age, attempts/failures and reference blocks. Audit identifiers and stable codes only; do not log owner names, receiver details, filenames, keys, JWTs or file bytes. Candidate lists and temporary diagnostics must not print private owner identities in reports.

## Acceptance plan for a later implementation

The following are required evidence, not tests executed by this document:

1. **Contract/privilege regression:** additive migration rollback preflight and all existing suites; existing buckets unchanged; unexpected Storage policies still fail allowlists; student/anonymous/cross-actor/disabled/ended/revoked denial; no client object read/delete/upsert, private direct grants, signed URLs or publication access. Preserve original upload projections and trigger invariants.
2. **Retirement correctness:** per-asset confirmation required; cancellation is read-only; active/expired/lost reserved entries are discoverable by bounded pagination; exact request replay is stable; operation reuse with changed identity/reason fails; unknown asset, uploaded history, unknown reference/hold and inconsistent lineage fail closed. No real values/roles are altered to isolate fixtures.
3. **Concurrency using independent sessions:** completion versus retirement in both lock orders; concurrent confirmations; prepare replay after tombstone; material/parent edits and reference acquisition; admission revoked while awaiting locks; duplicate attempt/expired-lease takeover and stale finalization. Sequential assertions alone are insufficient evidence of these races.
4. **Delayed Storage write:** pause a synthetic transfer after authorization, retire/expire it, observe temporary absence, then allow the late write. Prove there is no premature removal/final success. Verify the selected drain mechanism and uploads begun just before expiry. If a hard drain guarantee cannot be established, physical removal stays disabled.
5. **API integration with explicitly authorized synthetic assets only:** actual binary upload, one-key removal via Storage API, authoritative absence evidence, second reconciliation, malformed/mismatched metadata, response loss before/after deletion, denied deletion, delayed metadata visibility, provider errors and database/audit failure after removal. SQL metadata fixtures cannot establish these outcomes. Never execute SQL Storage deletes or bucket emptying.
6. **Retention/reference safety:** historical uploaded assets, recoverably deleted parents, any referenced/held asset and unrelated quarantine objects remain intact. A lost local reservation never causes a global sweep. Tombstones cannot be deleted, retargeted, reused for a fresh upload or reattached; later schema additions must participate in the barrier.
7. **Client/native acceptance:** explicit irreversible per-asset confirmation; no mutation on selection/cancel; account/background/access changes stop later effects; uncertain cleanup remains pending and reconciles without automatic removal. Main's current synthetic selection/cancel evidence is not binary-upload or cleanup acceptance.
8. **Fixture reconciliation:** use collision-failing synthetic IDs and track exact object keys/operation IDs. Database-only fixtures roll back and require zero-prefix readbacks; live API fixtures need a separate explicit API cleanup inventory because database rollback cannot restore/delete their bytes. Retained historical synthetic uploads are reported honestly until an independently authorized discard contract exists. Report aggregate counts/outcomes without owner identifiers or receiving data.

## Unresolved choices and rollout gates

No user question is required for this design. Record these for implementation review:

- Verified Storage drain/visibility/removal guarantees and deployment-specific limits. This is the primary correctness gate; no proof means continued retention.
- Server handler/runtime and credential isolation, narrow RPC privileges, request budget, safe absence verification and exact operation response schemas.
- Candidate eligibility wording and confirmation UX, immutable snapshot fields, reason enums, progress error codes and reference/hold inventory. Initial authority remains original uploader only.
- Grace periods, minimum ages, automatic retention, worker scheduling, operator recovery and historical-upload discard remain recommendations to evaluate, not approved policy. No timer authorizes deletion.
- Long-term audit/tombstone privacy retention and storage-cost reporting. Removing bytes must not silently remove provenance or recovery holds.

Roll out only after reviewed additive schema/functions, barriers and disabled-by-default handler are verified together; then enable synthetic acceptance separately. Any real owner-asset retirement/removal still needs explicit per-asset confirmation. This document does not authorize deployment, cloud writes, owner content edits, retention automation, credential provisioning or a push. Main retains independent ownership of native synthetic selection/cancel checks.
