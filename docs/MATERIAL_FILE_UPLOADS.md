# Session material uploads — staged implementation

## Scope and current gate

2026-10-24 upload-history display fix: uploading/checking clears list freshness
along with displayed rows. An uncertain response or a reserved-operation result
therefore cannot also assert an empty history without an actual list refetch.
Four regressions reproduced three failures before the fix; all four pass after
it, including the genuine-empty-refresh control. The exact bound request stays
locked and no retry/delete is introduced. Full verification/build results are
tracked in PROJECT_STATUS.md; no new native acceptance or cloud inventory is
implied by these synthetic widget tests.

Final main checks for that fix:1017app tests passed, clean analysis, locked
dependencies,84-file zero-change formatting and configured Android build57.6s.
Local APK189201892bytes, SHA256
614040C1BC437E37F3E4E6168A832E6AE65B892CE396D3656624C36EF64357D6.
It is not installed or native-accepted; prior8AC77native evidence is unchanged.
No backend test rerun, cloud mutation or push was performed in this follow-up.

Later2026-10-24 restart acceptance: current inventory is TWO distinct uploaded194-byte TXT records/objects (388declared-observed bytes), both unvalidated. The second operation predates the read-only run and has no established initiating source; preserve it. Normal process-restart/fresh history is now accepted on8AC77. See [updated inventory](MATERIAL_UPLOAD_BINARY_ACCEPTANCE.md) and [trusted validation design](MATERIAL_VALIDATION_DESIGN.md). Validation/attachment remain design-only; no worker or read capability enabled.

2026-10-24 update: actual synthetic194-byte TXT transfer, quarantine finalization and fresh close/reopen status accepted through the normal emulator app. Exactly one isolated synthetic draft/uploaded private test object is retained; not validated, attached, published, delivered or cleaned. See [binary acceptance and retained inventory](MATERIAL_UPLOAD_BINARY_ACCEPTANCE.md). Earlier checkpoint zero-object/no-transfer statements below are historical, not current inventory.

The owner requested actual upload controls after finding metadata-only material editing. Work on payment-instruction snapshots is paused; no destination-contract files were produced. This increment adds document selection and private upload staging for persisted PDF/file materials. Video hosting, Office/archive formats, trusted content scanning, attachment/readiness, publication, student delivery and PDF rendering remain separate gates.

Initial operational allowlist: PDF, and UTF-8 TXT for generic file materials; 20 MiB maximum. This conservative starting limit is not a fixed product requirement. PDF screening checks recognizable header/tail only; it does not establish structural validity, absence of active content or malware. TXT is strictly decoded and rejects binary/control content other than tab/CR/LF. Client screening is never a trusted server validation result.

New private bucket `material-upload-quarantine` is separate from existing `course-materials`, covers, receipts and assignment-submission buckets. Existing bucket configuration must remain unchanged. Upload completion means **uploaded—awaiting trusted validation**, never clean/ready/attached/published/playable or available to students. Quarantined files are not previewed, including for administrators.

## Flow and frozen client contract

Save material metadata as draft, then use its Upload file entry. Choose file → review selected filename/type/size → explicitly confirm upload → preparing/transferring/checking stages → persisted private upload status. Stages are indeterminate progress, not invented percentages. Cancellation sends no storage/upload request.

`MaterialFileUploadRequest` captures the initiating actor, immutable material descriptor/revision, owned immutable selected bytes and one operation UUID. Selection uses the official Flutter file-selector plugin (pinned 1.1.0) and bounded stream reads; fresh administrator admission is checked after native picker return. Only the native picker handoff bypasses ordinary background locking; account changes still invalidate it. See [official picker API](https://pub.dev/documentation/file_selector/1.1.0/file_selector/openFile.html).

- `prepare_material_file_upload(p_material_id,p_expected_revision,p_file_name,p_content_type,p_byte_length,p_operation_id)` returns exactly `asset_id,path,state`.
- Server path is `material_id/asset_id.pdf` or `.txt`, lowercase UUIDs; never a client path or original filename.
- `complete_material_file_upload(p_asset_id)` and `get_material_file_upload(p_asset_id)` return exactly `asset_id,material_id,file_name,content_type,byte_length,state`.
- `list_material_file_uploads(p_material_id)` returns at most twenty of those status records, newest first; no raw object path or transfer capability.
- State is only `reserved` or `uploaded`. Each status remains private administrator metadata, not student-facing catalog data.

Transport pins the initiating JWT on each RPC and fresh Storage API instance, rejects account switches including away/back, forbids global-header mutation, upsert and automatic retries. An uncertain result requires an explicit status refresh or Check upload; the latter repeats the original reservation identity then finalization without resending bytes. It never declares absence from a failed response or deletes an object on uncertainty.

## Server invariants and required verification

Use an additive CLI-generated migration, not edits to deployed migrations. Private asset ledger binds actor/operation/material/session/course, material revision, declared size/type, opaque identity/path, reservation expiry and quarantine status. Exact-input operation replay is idempotent; changed input is rejected. Validate filename/type/size/kind/revision and live nondeleted parents. Serialize account reservation caps before the existing course → session → material lock order; atomic audit failures roll back reservations/completion. Audits contain action and IDs only, not names, paths, bytes or hashes.

Storage permits only INSERT for the exact owned unexpired reservation under current server-controlled Admin admission; no SELECT/UPDATE/DELETE, overwrite, broad signed upload, direct ledger grants, student access or delivery URLs. Finalization rechecks actor/admission/parents/revision and exact observed Storage metadata before recording quarantine status. MIME/size are not trusted byte validation. See [Supabase upload access control](https://supabase.com/docs/guides/storage/security/access-control) and [consistent locking](https://www.postgresql.org/docs/current/explicit-locking.html#LOCKING-DEADLOCKS).

Neither material descriptor revision nor the existing media-publication block changes merely because upload succeeds. Later trusted scanning/validation and attachment require a separate reviewed transition. Replacement will require fresh object identity and atomic reference exchange; recoverable parent deletion must preserve assets. Cleanup requires an explicit, reference-safe Storage API lifecycle, not SQL deletion of storage object rows. Until implemented, abandoned/expired/quarantined objects remain retained private data and must be tracked for cleanup/storage cost.

Acceptance: exact-count rollback suite and all existing regressions, anonymous/student/ended/revoked/cross-actor denial, reservation expiry/caps/idempotency, byte/type metadata mismatch, stale revision and deletion during upload, no publication/direct-read bypass, audit-failure rollback, strict client projections/paths, account/lifecycle invalidation, picker cancellation, small-screen/large-text and uncertain completion. Real binary upload/readback requires a controlled synthetic fixture and trusted verification; SQL object-row fixtures alone do not prove bytes were uploaded. No real teaching material is authorized as a test fixture. Deployment and runtime activation require verified backend; main injection stays absent until then.

## Checkpoint discipline

### Native selection fixture and cancellation — 2026-10-23 follow-up

Final exact-snapshot verification after the selector fix: main passed all **1001 app tests**, clean analysis, locked dependencies, 83-file zero-change formatting and configured Android debug build (72.7s). APK 189202478 bytes, SHA-256 `8AC77EF18E5646A8FA380FCCF40A6F107286A36A991D3D045C3E4EDB2B0CBAD9`; installed with data preserved, base hash matched, ordinary restart restored Administrator home. On this artifact, native synthetic TXT selection showed exact194-byte/type/name metadata. Screenshots: `E:/Android-prerequisites-Summit/sea-selector-final-home.png`, `sea-selector-final-selected.png`.

Native boundary: before the next intended local-discard tap the workspace had changed to course list, so it opened a course-delete confirmation. Cancelled immediately, no deletion confirmed; hosted course remained archived/not-deleted and uploads/objects/orders remained zero. Cause of intervening navigation is unverified; no attribution or reproduced-defect claim. Stopped coordinate actions. Do not claim final-artifact discard acceptance; the earlier AB913 full confirmation/discard sequence retains its own evidence. Safe-cancel evidence: `E:/Android-prerequisites-Summit/sea-selector-final-safe-cancel.png`. No owner content was changed. Backend suites were not rerun for this client-only fix;992 assertions remain earlier evidence.

Subsequent selector fix: the post-picker length/read stage now has one absolute 20-second deadline, cumulative byte cap, auth/access-object and foreground checks, and stream subscription cancellation on every terminal outcome. It ignores late length results, observes late provider cleanup errors without retaining the selection lock, clears listeners/timers/buffers, preserves strict screening and still requires the shared final server-admission check. A pending native length call is not assumed physically cancelled; its late result cannot open a stream. The test clock is injected so deadline tests do not depend on incidental host speed. Agency engineer reports 30 selector / 116 combined focused checks passing; main's full exact-snapshot verification is recorded separately, not inferred from this report.

After cancelling the close/discard warning, hardware Back showed it again; explicit Discard and close returned to Materials. Reopening Upload file showed no local selection and the empty live upload history. Final readback: upload ledger=0, quarantine objects=0, orders=0. Additional evidence: `E:/Android-prerequisites-Summit/sea-native-discarded.png` and `sea-native-reopened.png`. Nothing was uploaded or deleted from cloud Storage. Cleanup is separately designed in [MATERIAL_UPLOAD_CLEANUP_DESIGN.md](MATERIAL_UPLOAD_CLEANUP_DESIGN.md), not implemented or enabled.

On the unchanged `AB913E5D…37416` debug artifact, the native document provider selected the repository fixture `app/test/fixtures/sea-native-upload-synthetic.txt`: 194 bytes, SHA-256 `8A86767468A9716F8093AE38E577EF11AC5EBB62DFDFC41DB0FDD0F49AD1ACED`. The app showed the exact basename, size and `text/plain` with “Selected — not uploaded.” Opening upload confirmation and choosing Cancel retained the selection. Closing uploads displayed the discard warning; Cancel retained it. No Confirm upload was pressed and no owner metadata was changed. Server readbacks before/after confirmation cancellation: upload ledger=0, quarantine objects=0. This is native selection/confirmation evidence, not real Storage transmission, PDF/Huawei/iOS or trusted validation acceptance.

Screenshots outside Git: `E:/Android-prerequisites-Summit/sea-native-selected.png`, `sea-native-confirm.png`, `sea-native-confirm-cancel.png`, `sea-native-discard-dialog.png`, `sea-native-discard-cancel.png`, `sea-native-back-discard.png`. Synthetic fixture remains explicitly nonsensitive and may stay on the emulator for reproducible acceptance; no downloads or owner files were removed. A separate abnormal-provider read-deadline/cancellation defect found during review is being fixed; this normal-file exercise does not close it.

### Verified development checkpoint — 2026-10-23

Native follow-up: Android picker cancellation returned to the same enabled empty upload panel after fresh admission. Final server readback remained uploads=0, objects=0, orders=0. Evidence outside Git: `E:/Android-prerequisites-Summit/sea-upload-panel.png`, `sea-upload-picker.png`, `sea-upload-cancel.png`. No real teaching file or owner metadata was changed. Next binary acceptance must use clearly labeled synthetic bytes and track retained private data/storage cost until reviewed reference-safe cleanup exists; do not delete Storage rows via SQL or invent a clean/ready result.

Deployed as `20261023112810_phase2_material_file_uploads.sql`; local filename aligned to actual hosted history. All eleven suites passed consolidated additive rollback preflight and fresh postdeployment, **992 assertions**: identity 84, admin sessions 46, content 130, covers 53, materials 163, catalog 155, bookmarks 84, cleanup 29, pending orders 70, instructor setup 79, uploads 99. All eleven upload-fixture cleanup counts were zero. Existing real receiving profile/course binding each remained one; uploads, quarantine objects and orders remained zero. All four anonymous HTTP upload RPCs denied 401/42501. Storage metadata fixtures are not binary upload evidence.

The instructor-directory suite now captures a privileged count-only baseline and verifies ordered pagination with fixtures; it no longer incorrectly assumes the development directory contains only test users. Existing storage-policy regression allowlists admit only the new named INSERT policy; unexpected policies still fail. The new policy assertion checks authenticated INSERT only and the exact quarantine bucket/helper boundary.

Configured main now injects the upload service after backend verification. Main passed all **978 app tests**, clean analysis, locked dependencies, zero-change formatting across 83 files and configured debug Android build (17.1s). APK: 189196702 bytes; SHA-256 `AB913E5DEF6EDD15ECB5D8CA028040B449D6127D163E1B55D47CBB5D9CD37416`. Installed with existing data preserved; installed base hash matched and Administrator home restored. Existing archived synthetic course/session and owner-added draft file metadata were opened read-only: Upload file led to the live empty quarantine panel; Choose file opened Android's native document picker. No owner material was edited or file selected. Binary/uncertain-result acceptance is still open. The earlier statement about absent injection describes the prerequisite, not current runtime wiring.

Agent review found and main fixed stale phase/check callbacks allowing later side effects after access loss, stale card entry after replacement/disposal, and retained second-card callbacks silently replacing selected/uncertain uploads. Regression coverage includes real HTTP no-finalization after reconciliation loses foreground access, and two-material selected/uncertain preservation. Final bounded client/backend reinspection found no remaining concrete blocker; this is not an executed Claude Code audit or production security certification.

Postdeployment advisors: one new intentional closed-ledger [RLS/no-policy INFO](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), four new [unused-index INFO](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index). Existing [material composite-FK INFO](https://supabase.com/docs/guides/database/database-linter?lint=0001_unindexed_foreign_keys) and [leaked-password warning](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) remain. No blanket grants, index deletion or paid settings were used to hide them. New workflow suite remains unpushed and has no remote CI evidence.

Agency Backend Architect owns the migration and rollback suite; Mobile App Builder owns selection validation and the upload panel; Mobile Upload Verification Engineer owns transport tests. Main owns native picker/service wiring, integration, independent checks and status. No push follows without fresh explicit approval. Record actual test/deployment/device outcomes in PROJECT_STATUS.md; this design alone is not acceptance or an executed Claude Code audit.
