# Trusted material validation and attachment — review before implementation

Status: live validation remains design only, 2026-10-24. A separate [offline byte-observation prototype](../tools/material-validation/README.md) now exercises synthetic in-memory streams; it cannot establish Storage identity/generation or grant readiness. No scanner, server byte read, credentials, Storage read policy, schema, production runtime, paid service, attachment, publication, delivery or cleanup is implemented or authorized here. Live implementation must be reviewed separately before deployment.

## Current evidence and boundaries

Basis: Agency Backend Architect guidance, [upload contract](MATERIAL_FILE_UPLOADS.md), [cleanup design](MATERIAL_UPLOAD_CLEANUP_DESIGN.md), [binary acceptance](MATERIAL_UPLOAD_BINARY_ACCEPTANCE.md), and the existing upload/protected-payload migrations. Existing design proposals are not evidence of deployed capabilities.

Main's latest restart readback reports **two retained quarantined upload records/objects, both unvalidated**, for synthetic material `120268dd-c129-42f5-8255-07c9dd859992`. Each declares 194 bytes and has Storage-observed size 194 with MIME `text/plain`: 388 declared bytes total, with matching aggregate metadata sizes. The first asset is `c894787d-2424-4c8d-8fd2-2e94b63db5e6`, recorded at `2026-10-23T21:19:24Z`; the second is `85a2c035-d125-4ba0-9b1a-40e533feb07a`, operation `0906cc7a-fa1c-48af-9d70-0c6331f7a7b4`, recorded at `2026-10-24T00:03:14Z`, before the current read-only run. Material remains draft revision 1, course archived, orders zero. Preserve both. No UI upload was initiated this turn; the second record's initiating source is not established, and this observation does not establish a duplicate-retry defect.

Normal-app transfer and close/reopen status were accepted for the earlier checkpoint. The repository fixture SHA-256 is a local-file digest; neither that digest nor matching Storage metadata establishes a hash of either server-held object or equality of their actual bytes. The ledger's request hash covers typed reservation inputs, not file contents. No server byte read/hash, parser verdict, clean result or malware scan has been accepted for either asset.

Main independently owns process-restart/read-only quarantine-status acceptance and the morning note. Reopening or restarting cannot validate bytes, attach an asset, or authorize new cloud writes. This design preserves the reported two-object inventory and owner content/authentication state. Inventory above is main's supplied readback, not an API check or test performed for this document.

Scope remains PDF and UTF-8 TXT under the current private quarantine bucket and 20 MiB limit. Other formats, video, external URLs, Office/archive files, renderer selection and content exports are outside this increment. Existing buckets remain unchanged. No client/admin quarantine preview, signed URL or general read policy is added to obtain evidence.

## Independent gates

| Gate | Meaning and authority | What it does not grant |
| --- | --- | --- |
| Uploaded | Existing metadata completion under current administrator admission | Byte identity, validation, attachment or access |
| Observed immutable bytes | Trusted acquisition binds exact complete bytes to a durable object generation and SHA-256 | Content acceptance or readiness |
| Validation accepted | All required parser/scanner checks accepted for that generation under a named current policy | Material reference, publication or delivery |
| Attached | Separate explicit administrator transaction binds a current accepted proof to this material | Publication, student entitlement or read capability |
| Publication eligible | A separately reviewed readiness contract checks current references and all lifecycle requirements | Delivery authorization |
| Delivery authorized | Future resolver checks current admission/device, entitlement, published parent chain, current valid proof and permitted action | Generic downloads, permanent URLs or offline rights |

Keep existing upload states `reserved`/`uploaded` and frozen three-/six-field RPC projections unchanged. Store validation evidence and attachment references separately. Do not relabel uploaded history as `clean`, `ready` or `attached`. A positive validation result means only that specified checks passed for specified bytes; it is not a guarantee that a document is harmless or all future parsers are safe.

The current protected payload stores assignment body/link target, not an attached validated file reference. A later private attachment reference must be explicit and material-owned. Existing media publication guards remain closed throughout initial observation/validation/attachment acceptance. Opening publication or delivery needs independent review and acceptance.

## Trust and authorization contract

An initial validation request should come from the admitted original uploader for one existing `uploaded` asset, with an operation UUID and expected material revision. This is a narrow initial recommendation; cross-administrator validation/recovery is unresolved. Expired reservations are not silently completed or read by the worker. A missing/lost completion response must reconcile through the existing completion/status contract first.

Resolve the immutable bucket/key and material lineage on the server from the asset ID. Accept no caller URL, bucket/key, local hash, MIME verdict, `clean=true`, worker identity or scanner configuration. JWT `user_metadata`, filenames, mobile screening, extension, Content-Type and Storage metadata are untrusted declarations for validation purposes. Current server-controlled account role/admission authorizes initiation; worker authentication is separate and never impersonates an administrator by changing roles or owner session/device records.

A future worker receives one job/generation capability through an authenticated internal channel. Limit it to the exact object and recording bounded evidence; no general listing, deletion, arbitrary URL fetch, owner payment data or public read grant. Runtime, credential mechanism, secret storage/rotation and egress allowlist must be selected during implementation review. A broadly privileged service credential, if unavoidable, stays isolated server-side behind exact-job enforcement; its role bypass is not authorization. No such credential or grant is created now.

Anonymous/student/mobile callers cannot submit accepted verdicts, revoke server evidence, update proof columns or select private evidence tables. An administrator can request work and inspect a safe summary, but cannot override unavailable/rejected results or choose an older policy to obtain acceptance. Any future worker RPC requires explicit narrow grants, an empty search path, job/generation/worker verification and private RLS. Default PUBLIC execution and broad service table privileges must remain closed.

## Exact-byte acquisition and immutable identity

Before claiming a job, verify uploaded state, complete immutable lineage, current admission, expected material revision, no deleted parent, no cleanup tombstone and no incompatible active operation. A short transaction records a job and snapshot; no database locks or transactions stay open during Storage reads or parsing.

The trusted fetcher must acquire one complete binary stream through an authorized Storage API path, restricted to the server-resolved exact object. Stream with a hard maximum of 20 MiB plus one overflow-detection byte, exact observed byte count, absolute deadline and cancellation. Reject incomplete/truncated bodies, unexpected content encodings, redirects to unapproved targets, excessive size, empty content, identity changes and declared/observed size mismatch. Error/denied access does not prove absence. Do not hash a normalized TXT string or a decoded PDF representation as the source-object digest.

Compute SHA-256 over the complete original byte sequence and persist the observed byte length and server-detected type. Compare to declared MIME/size as additional consistency checks. Metadata size, an ETag without documented content semantics, a UUID key, and the absence of a client UPDATE policy do not by themselves prove immutable server bytes.

Bind evidence to `(asset_id, server-resolved object identity, immutable generation/version, SHA-256, observed length, detected type)`. Establish and test a provider generation/conditional-read mechanism or an equivalent immutable snapshot protocol before implementing positive results. Pre/post metadata reads alone cannot eliminate an overwrite/ABA race. If the provider cannot bind reads and future consumers to the same immutable bytes, record `unavailable`; do not accept a path-only proof.

Hash, parse and scan the same bounded snapshot, using a sealed read-only temporary handle or equivalent verified mechanism. Do not independently refetch the path for each check. A separate scanner process must attest the exact digest it scanned; the trusted coordinator verifies this against its own digest and job identity. Temp files use non-user-controlled names, isolated storage and restrictive access; disposal of worker temporary copies does not authorize removal of the quarantine original.

Future attachment and delivery must bind to that immutable generation. If the backend can only fetch a mutable key, it needs a separately reviewed sealing/content-version strategy before attachment can be enabled. Any generated/sanitized derivative is a new immutable asset with provenance and its own required validation; it cannot inherit the source verdict or silently replace source bytes.

## Parser and scanner policy

Define a reviewed versioned policy profile covering required stages, allowed formats/features, engine/build/configuration versions, signature database version/freshness, resource limits and positive-result validity rules. Store its immutable digest with every attempt. No vendor, runtime, scanner service, subscription or deployment is chosen implicitly here. If a required stage is unavailable, even for TXT, the entire attempt remains ineligible.

Run hostile-file parsers/scanners in disposable isolated processes with no database/Storage credentials, no ambient secrets, no network or URL resolution, bounded CPU/wall time/memory/output/process count, read-only input and controlled temporary storage. Fetch credentials stay in the trusted coordinator. Parser output is untrusted structured input with a strict size/schema allowlist; never render extracted HTML, execute actions, run macros, invoke shell handlers or trust free-text diagnostics as commands.

Proposed conservative PDF policy: verify complete structural parsing rather than header/EOF heuristics; reject malformed/truncated or ambiguous/polyglot content and unsupported features. Encrypted/password-protected documents, embedded files, JavaScript, launch/automatic actions, external fetches and other active features remain unsupported unless a later policy explicitly handles them. Bound page/object counts, nesting, decompression and embedded-resource processing. A parser that cannot reliably detect a prohibited feature returns unsupported/unavailable, not accepted. Scanner acceptance alone cannot substitute for structural policy compliance.

Proposed TXT policy: strictly decode complete original bytes as UTF-8 without replacement; reject malformed encodings and prohibited binary/control content. Define the exact Unicode/control/BOM allowlist in the versioned policy, at least preserving the current tab/CR/LF exception and rejecting NUL. Extension/MIME/printable samples are insufficient. Decide ambiguous text/polyglot handling explicitly; uncertainty fails closed. Future presentation must escape text and disable active HTML/Markdown/URL behavior unless separately reviewed. This document creates no text viewer.

Exact thresholds, parser coverage, scanner/signature freshness and residual-risk acceptance are unresolved implementation gates. Proposed format rules are a review starting point, not a claim that a selected engine implements them.

## Versioned verdicts, retries and safe proof

| Attempt outcome | Meaning | Effective eligibility |
| --- | --- | --- |
| `pending` / `running` | Work queued or leased; result not committed | Deny |
| `accepted` | Every required stage succeeded for the exact snapshot/policy | Candidate only, subject to all current checks |
| `rejected` | Positive policy violation or prohibited content identified | Deny; retain quarantine |
| `unsupported` | Format/feature cannot be safely handled by the required profile | Deny; retain quarantine |
| `unavailable` | Runtime, credential, scanner, signatures or identity proof missing/stale | Deny; retain quarantine |
| `timeout` / `error` | Resource/deadline/transport/parser/scanner failure or malformed result | Deny; retain quarantine |
| `stale` / `cancelled` | Job/context/generation is superseded or invalidated | Deny; retain history |

Keep revocation as an append-only fact referencing a proof or policy/engine generation; never overwrite an old accepted evidence record to hide what occurred. Effective acceptance must be computed from current policy, revocations, object identity and context, not a permanent cached boolean. No “last successful result wins” fallback after a newer invalidating result or mandatory policy change.

Proposed private records: actor-scoped request/idempotency identity; immutable object observation; immutable policy profile; immutable attempt evidence; versioned active-job pointer/lease generation; append-only proof/policy revocations; and a separate current attachment reference. Evidence includes asset/job/attempt IDs, digest and generation, byte count/type, parser/scanner/config/signature versions, bounded stage result codes, worker identity and server start/finish times. Digests and locators remain private evidence, not public catalog fields or broad logs.

Callbacks must authenticate worker and audience, bind job/attempt/generation and exact observed digest, enforce a server deadline/lease, and reject unknown stages, extra payloads, stale engines/policies and incomplete results. Exactly repeated result submissions are idempotent and audited once; changed results with the same event ID conflict. Lease takeover fences old results; late callbacks cannot revive superseded work. Never let a callback supply the attachment/current-reference decision.

Numeric fetch/parser/scanner deadlines, retry counts, backoff caps, concurrency limits and queue capacity must be explicitly set and tested before enabling a worker; no unbounded default is acceptable. Only classified transient failures may receive bounded retries with fresh attempt IDs and the same verified immutable generation. Unsupported/rejected results are not retried until a reviewed policy/tool change warrants a new request. Queue exhaustion, scanner outage and expired signatures fail closed; no paid fallback or external file submission is implicit.

Minimal administrator status should contain asset/material/request IDs, stage/outcome, policy identifier, observation/decision times and safe reason codes. No raw bytes, parser excerpts, object path, signed URL, worker credentials or full hash is needed. Hash/proof details are restricted to authorized backend evidence inspection. Errors must not echo original filenames, file text, SQL or provider response bodies.

## Staleness, revocation and shared consumer locks

Snapshot the upload's expected material revision and current requesting actor/admission identity when queuing. Initial implementation requires them to match the current material revision; metadata edits do not silently rebind an old upload. A future safe rebinding workflow is a separate choice. Expected revision mismatch requires explicit reconciliation/new reviewed intent, not automatic overwrite or reupload.

Recheck current authorization, nondeleted lineage, revision, immutable generation, current policy/signature requirements, proof revocations and tombstones when accepting the callback and again when attaching. Parent draft/archived state may permit private validation under the existing preparation rules; deleted parents do not. Neither archived parents nor restored-to-draft parents imply student visibility. Completion of validation never edits parent state or descriptor revision.

If the initiating session/account/admission is ended, expired, revoked, disabled or demoted while work runs, fetched evidence may remain restricted history but cannot become an effective positive authorization. Record cancelled/stale status and require a new authorized request; do not reset owner sessions/devices. A worker is not a permanent proxy for the initiating administrator. Attachment always requires fresh acting administrator admission, regardless of prior worker success.

For schema-changing implementation, use a shared ordering compatible with upload/cleanup: account/admission → course → session → material → involved asset rows in deterministic UUID order → active validation/proof generation → consumer reference/operation. Inventory existing mutation paths for inversions before accepting this ordering. All reference creators, validation consumers and cleanup claimers must acquire the same asset barrier and reject tombstones. Unknown consumers block activation. No transaction spans external reads/parsing/scanning.

Policy/proof revocation must serialize against attachment acceptance through a policy-generation/proof lock or equivalent tested atomic check. A callback cannot make an old engine/signature generation current again. Existing attachments may retain their historical mapping after revocation, but immediately become ineligible for publication/delivery through mandatory current-proof checks. Do not automatically delete bytes, erase evidence, detach parent content or pretend an already-issued future bearer capability is revoked instantly. Capability lifetime/revocation behavior belongs to the delivery gate.

Cleanup tombstones permanently defeat validation/attachment. The current reserved-only cleanup proposal leaves historical uploaded assets retained, so it does not authorize removal of this accepted-upload fixture. If uploaded-asset cleanup is later designed, validation work must register a fenced consumer hold before fetching and removal must exclude live holds as well as attachment references. An expired lease alone does not prove an external reader/writer stopped; resolve late work using the cleanup drain/barrier requirements. No retention timer or failed verdict authorizes deletion.

## Separate explicit attachment transaction

Proposed input: material ID, asset ID, accepted proof ID, expected descriptor revision, expected current asset (including explicit null), current policy generation and actor-scoped operation UUID. The server derives all protected identities. Reject different input reusing an operation UUID; exact replay returns the prior mutation result only after current authorization and safe reconciliation, not an obsolete delivery capability.

Under shared locks, require matching asset/material/session/course lineage, uploaded state, stable immutable generation, complete accepted proof under current policy, no revocation/tombstone/hold conflict, compatible PDF/file kind, current revision/current-reference CAS and nondeleted parents. Use a composite material/asset ownership constraint for the private reference; apply equivalent scoped ownership to future resource references. Reject cross-material attachment even if the actor owns both.

In one transaction, install the private reference, increment the material revision exactly once, preserve draft status, write operation result and IDs-only audit. Audit failure rolls the transaction back. Initial attachment accepts an explicit null current reference only. Replacement remains gated until its full atomic reference-exchange and old-asset retention contract is reviewed; a later replacement must lock both assets, preserve existing consumer references/history and never automatically delete the previous object.

Do not extend the current upload row to hold mutable reference/readiness fields, modify existing deployed migrations, or relax media-publication checks as a shortcut. A new attachment schema/RPC and corresponding guarded consumers require an additive review. Link/assignment private payloads remain private; validation cannot populate them with raw file text or a transferable object locator. Soft-deleted descriptors retain references for recoverable restoration; restoration does not bypass revalidation/current policy.

Attachment must not generate signed URLs, preview bytes, an entitlement, order, payment change or student catalog exposure. Even an attached accepted asset is undeliverable until the independent publication/readiness and action-specific delivery contracts pass.

## Audit, operational evidence and rollback

Audit successful request, accepted result, revocation and attachment transitions atomically with their private records, using correlation/operation/asset/material/proof IDs and stable codes only. Never copy bytes, hashes, names, paths, receiver information, credentials or parser text into general security events. Maintain exact stage/version evidence privately; metrics use aggregates for pending age, timeout/unavailable/rejected counts, generation conflicts and storage retained. Scanner success counts are not “malware-free” claims.

Separate SQL contract tests, mocked worker tests, actual isolated parser/scanner tests and native acceptance in reports. Fixture metadata cannot prove full byte acquisition; a local digest cannot prove server bytes. A scanner version label without authenticated exact-digest provenance cannot prove which file was checked.

On rollback, disable new requests/worker execution/attachment consumption while preserving evidence, references, policy revocations and cleanup tombstones. Never restore functions that ignore barriers or make revoked evidence effective. All unimplemented or unhealthy validation paths continue to show awaiting validation/unavailable. No rollback deletes retained objects or changes owner authentication/content.

## Phased implementation and acceptance

These phases are a review plan, not permission to execute them now. Each phase requires concrete reviewed contracts, bounded configuration and distinct evidence before proceeding.

1. **Contracts and isolated fake workflow:** finalize machine-readable request/result/status schemas, policy profile and privilege matrix; implement private observation/job/proof/revocation records in a separately reviewed additive migration. Test exact-input idempotency, extra/malformed/stale callback rejection, worker/mobile/anon/student privilege boundaries and audit-failure rollback. Keep all byte readers and attachment disabled. Run existing regressions with real baseline data preserved; assert synthetic fixture cleanup separately.
2. **Trusted acquisition only:** select and prove immutable generation/snapshot binding, fetch credentials isolation and byte limits using explicitly authorized disposable synthetic objects. Verify complete server bytes hash/size against independently known fixtures; exercise truncation, overflow, declared metadata mismatch, denial/redirect, mutation/ABA, replacement and late writes. Observation creates no accepted verdict or read policy. Do not read the currently retained fixture without separate authorization.
3. **Isolated PDF/TXT validation:** review engine/policy choices and exact numeric budgets; test corpus includes valid documents, malformed PDF, encrypted/active/embedded-feature PDFs, decompression/resource bombs, UTF-8 errors/control text, ambiguous/polyglot inputs and scanner test signatures in isolation. Verify prohibited outbound requests, parser sandbox escape assumptions, output limits and exact-digest provenance. Unsupported features, stale signatures, outages, timeout, crash and partial checks must never become accepted. No public service submission or paid provision is implied.
4. **Real concurrency and revocation:** use independent sessions/workers for policy/proof revocation versus callback/attach, admission revocation while blocked, parent deletion/revision drift, duplicate job/callback, worker lease takeover, tombstone/reference acquisition and stale-generation completion. Verify both interleavings and zero partial references/audits. Sequential CAS checks alone do not establish these races.
5. **Attachment only:** separately review the private ownership reference/RPC and consumers. With synthetic assets, prove current-null/reference/revision CAS, cross-material denial, proof/generation mismatch rejection, revocation invalidation, exact replay, audit rollback and recoverable parent/reference retention. Preserve media publication denial, private payload boundaries and zero student delivery. Replacement is a later explicit subphase unless its full contract is separately accepted.
6. **Independent publication/delivery readiness:** leave disabled until entitlement/current-session/device, complete parent lifecycle, current validation and action permission checks are implemented and accepted. PDF view-only/no-offline constraints need their own renderer/capability review; receiving bytes cannot be claimed uncopiable. Test native student denial, guessed IDs, free-preview cases and stale/revoked proofs without granting quarantine reads.

Preserve both existing 194-byte objects (388 declared bytes total), their distinct asset/operation identities and their unvalidated status; distinguish them from rollback-generated IDs. Live binary fixtures require an exact retained-object inventory; SQL rollback does not remove their bytes. No SQL Storage deletion, bucket emptying, age-based purge or owner content change belongs in acceptance. Synthetic removal still needs a separately authorized applicable cleanup contract. Record remaining retained objects honestly.

## Unresolved implementation choices

The [worker isolation acceptance plan](MATERIAL_WORKER_ISOLATION_ACCEPTANCE.md)
now records the fresh local Linux-runtime limitation and the proposed proof
sequence. The offline observer passed122tests after a cancellation-order fix;
neither that result nor this plan closes the unresolved live choices below.

- Runtime/worker isolation and parser/scanner engines, licensing/cost, update provenance, credential scope/rotation and permitted egress. None is selected or purchased.
- Provider immutable generation/conditional-read semantics or an equivalent snapshot/sealing protocol that future consumers can enforce. Without proof, positive validation/attachment stays unavailable.
- Exact PDF feature allowlist, TXT Unicode/BOM/polyglot handling, all resource/time/queue budgets, signature freshness, policy validity/revalidation and emergency revocation behavior. No implicit “TXT needs no scanner” exemption.
- Private record/RPC schemas, policy-lock ordering, reference inventory, consumer holds, callback authentication and initial same-uploader request model. Cross-admin recovery and metadata-revision rebinding require separate decisions.
- Replacement, validation of derivatives, publication, delivery, rendering, historical uploaded-asset discard and retention periods are distinct later gates. No schedule or retention time is approved here.

The next concrete deliverable should be a reviewed contract/configuration proposal addressing these choices before implementation. This design grants no scan/read credentials, read policy, actual scan, cloud write, publication, cleanup, deployment or push; main continues independent process-restart/read-only status acceptance.
