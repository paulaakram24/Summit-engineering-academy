# Administrator material editor — delivery checkpoint

Completed locally and accepted on the Huawei debug build on 2026-10-19 after owner-approved foundation push 5fa6d4a. This separate UI increment remains unpushed and requires fresh approval. See ROADMAP.md 2.3.3 and PROJECT_STATUS.md; this is not full Phase 2, student delivery or release acceptance.

## Navigation and authority

Manage courses → Sessions → Materials for a persisted, nondeleted course/session. MaterialRepository is injected from the same signed-in Supabase runtime through SummitApp/AuthPanel; no second session, key or service-role client. A missing dependency does not expose a broken entry point. Students have no authoring entry; the deployed RPC/RLS administrator/device/session checks remain authoritative.

The panel must discard protected state on access loss or account/device changes, including a close/reopen before the next frame. Pending asynchronous callbacks cannot restore an old list, assignment body, link target, editor or confirmation. Existing application background locking stays active; there is no native-picker exemption for material authoring.

## Authoring slice

- Twenty-item session-scoped lists, stable repository ordering, Include deleted, refresh, empty/error/loading states and bounded pagination.
- New material kind, safe title/summary and integer order; create always starts draft. Existing kind/session/creator/ID are immutable.
- Assignment body is protected plain text; link target is nullable supported HTTPS text. Fetch private administrator detail before enabling edits; never reconstruct payload from list metadata. No external URL launch or fetch.
- Video/PDF/file are metadata placeholders only. No upload/download controls or student delivery. They cannot publish until later validated assets exist. PDF view-only and server-entitled delivery remain future integration requirements, not granted by this UI.
- Publication of configured links/assignments is administrator authoring state, not proof of student availability or paid access. Physical temporary acceptance content must remain draft.
- Confirm recoverable delete/restore; cancellation sends no mutation, restore returns draft. Deleted parents/items cannot be edited through stale cached controls.

## Mutation and recovery requirements

Capture actor and operation ID once per user intent, expected revision for edits/lifecycle, and immutable request fields. Prevent duplicate taps. Refetch current list/detail after every success, including cached responses, before exposing current lifecycle/edit controls. Do not merge a cached historical snapshot into current state.

Uncertain transmission may already have committed. A conservative refresh-only recovery is acceptable: explain uncertainty, block new mutation until refresh and reconcile current state. Never automatically issue a new create intent or silently change an exact retained retry. A revision conflict cannot overwrite a newer revision automatically. Cross-account retries are prohibited by the verified repository.

Sanitize visible errors; do not log form fields, bodies, targets, tokens or raw backend responses. Dispose controllers and remove modal content on loss of access. Keep explicit Cancel/back navigation and unsaved work handling usable with a keyboard and enlarged text.

## Verification plan

1. Panel widget tests: kind-specific validation; detail-first editing; media readiness; confirmation cancellation; restore-to-draft; pagination/filter reset; duplicate-tap suppression; uncertain/conflict refresh; cached reply refetch.
2. Access tests: student/missing identity/changed actor or device; background/suspend; rapid reopen; late list/detail/mutation response after access loss; removal of protected editor/dialog contents.
3. Integration tests: injected repository reaches the selected session through app navigation; no Materials entry without dependency; deleted session disables entry; closing returns to refreshed session list; role loss closes workspace.
4. Complete analysis, dependency/format checks, Flutter tests and Android debug build. Record exact totals and actual independent review, not assumed acceptance.
5. Physical Huawei: use only the already owner-authorized temporary course/session, synthetic text and example.invalid links. No publication, purchase, real student data or paid service. Verify persistence and recoverable lifecycle, then soft-delete the temporary course again. Keep screenshots outside Git; no admin logout is needed.

No new schema/migration is planned for this UI slice. No push is authorized for these follow-up changes until tests and fresh owner approval.

## Recorded verification

Main passed locked dependency resolution, clean analysis, 355 app tests, formatting across 40 Dart files with zero changes, and the configured Android debug build (8.4s). Included: 38 panel tests, 5 full entrypoint tests and 107 material model/repository checks. Mobile App Builder implemented the panel; main integrated the runtime/entrypoint and independently ran the full checks. Mobile Release Engineer's final bounded read-only inspection found no unresolved concrete defect; this is not an executed Claude Code or comprehensive security audit.

Installed APK: 189013765 bytes; SHA-256 `932540DBECDE281CF0582BCB94E0F8242B6FA1B6442719CD078E14093E42D054`. Huawei ANE-LX1, Android 9/API 28. Saved draft assignment, edited its title after loading private instructions, cancelled deletion (revision unchanged), confirmed deletion, included deleted records and restored to draft (revision 4, 35-character instructions retained). Saved an inert `https://example.invalid/sea-test` link and video metadata placeholder. Force-stop/restart preserved the owner session and all three records; opening link detail fetched the original private target, without launching it. Reopened video remained draft and displayed the no-upload/no-delivery warning. No publication was attempted; no media bytes were uploaded.

Final temporary course was soft-deleted again through the app. Settled default course list is empty; independent hosted readback confirms archived/deleted, no cover and three retained draft materials under its draft session. All acceptance records remain recoverable. Screenshots and scoped audit details are in docs/PHASE2_DEVICE_ACCEPTANCE.md. Slow initial white startup eventually rendered; no launch-time performance acceptance is claimed. iOS, release signing, student HTTP/material access and real concurrent editing remain open.

Approved foundation push 5fa6d4a passed both remote workflows: Flutter 39280706648 and Backend 39280706650. These remote results do not verify this later unpushed UI increment. No backend code changed for the editor; the earlier 430 passing database assertions are the foundation result, not a fresh rerun attributed to this UI.
