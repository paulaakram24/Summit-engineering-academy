# Phase 2 development-device acceptance — 2026-10-19

Device: owner-authorized Huawei ANE-LX1, Android 9/API 28. Installed configured **debug** APK, not a signed production release candidate. Previous local checkpoint: 171 Flutter tests, clean analysis, configured Android build passed in 36.5 seconds. Later cover UI changes require fresh checks and installation.

Device package readback: versionName 1.0.0, versionCode 1, minSdk 24, targetSdk 36, DEBUGGABLE flag. This development version is not a store submission identifier.

Metadata/lifecycle debug APK SHA-256 before the next cover build: `88fccfe0234cf0014b91d86a650b15a200261ff8981570b3da4a9b9e660c64f1`. Direct device `base.apk` hashing matched the local 188,765,114-byte artifact. This is a development artifact, not a pushed release.

Owner explicitly allowed temporary content. All physical writes used the normal administrator application and its authenticated API. Hosted checks below were read-only; no service-key bypass was used for phone operations.

## Accepted administrator flows

1. Empty course submission remains in editor with required-field errors.
2. Create `SEA-TEMP-20261019`, description `Temporary-device-test-not-for-sale`, instructor `SEA-Test`, category `Testing`, level `Acceptance`, position 0, price 123.45 EGP, draft.
3. Reopen editor and verify persisted description/metadata/price; append `-EDITED` to title and save. List shows edited title, unchanged exact price and draft status.
4. Create session 1 `TEMP-Session`, description `Temporary-session-test`, position 0, price 12.34 EGP, draft, free preview off. Reopen editor to inspect persisted values, append `-EDITED`, save and verify list.
5. Open session deletion confirmation and Cancel: session remains unchanged. Confirm deletion on a second attempt: absent from default list. Include deleted shows archived/Deleted, Edit disabled, Restore available. Restore confirmation explains explicit republication; restoring returns draft with edited title and price intact.
6. Delete parent course: Include deleted shows archived/Deleted with Edit course and Sessions disabled. Restore returns draft with title/price intact and editing/session controls enabled.
7. Final cleanup soft-deletes the same course again; all records remain recoverable. Its restored draft session remains under the deleted parent. Nothing was published or permanently deleted.

Read-only hosted readback independently confirmed exactly the designated course (`354b334e-72fb-437b-b430-08527c539a6a`) and session (`d92d2362-64be-459b-b1fb-346602707ccd`): course archived/deleted at final check, session draft/not individually deleted, prices 12345 and 1234 integer piasters. These identifiers refer only to explicitly authorized temporary development content, not fictional rollback fixtures.

Scoped audit readback: course one draft insert, two draft updates (edit/restore), two archived/deleted updates; session one draft insert, two draft updates (edit/restore), one archived/deleted update. No published event was present for either designated entity. Cancel generated no extra mutation.

## Private local screenshots

Stored outside Git under `E:/Android-prerequisites-Summit/`:

- `sea-temp-result.png`, `sea-temp-edit-ready.png`, `sea-temp-edited-list.png`: course create/read/edit.
- `sea-session-created.png`, `sea-session-edit.png`, `sea-session-edit-result.png`: session create/read/edit.
- `sea-session-confirm.png`, `sea-session-cancel.png`, `sea-session-deleted-ready.png`, `sea-session-deleted-visible.png`, `sea-session-restore-confirm.png`, `sea-session-restored.png`: cancellation, deletion and draft restoration.
- `sea-course-delete-confirm.png`, `sea-course-deleted-visible.png`, `sea-course-restore-confirm.png`, `sea-course-restored.png`, `sea-temp-final-deleted.png`: parent lifecycle and final recoverable state.
- `sea-temp-final-hidden.png`: final default list is empty with Include deleted off.

Screenshots during Saving/loading are transition evidence only, not successful completion. Final readback and settled screenshots establish the stated results.

## Remaining gates

- Physical student-side denial/visibility, explicit publication behavior and release-signed artifact acceptance.
- Student-side cover visibility/denial, iOS picker behavior and release-signed cover acceptance; administrator binary flow accepted below.
- System Back currently lacks an unsaved-change warning; use explicit Cancel/Back to courses deliberately.
- Price helper's earlier large-font truncation was addressed in the cover UI increment; other forms still require release-wide accessibility checks.
- No claim of live email/recovery, second-device, iOS, production readiness or hosted CI for unpushed changes.

Agency Agents Mobile Release Engineer guidance informed cancellation, restore-to-draft, exact-price readback and the distinction between debug acceptance and release acceptance. Push requires fresh owner approval.

## Private cover acceptance — 2026-10-19

Same authorized unpublished temporary course. Controlled picker input was only the repository logo copied to Download/SEA-TEMP-cover-test.png; personal files were not opened. Picker cancellation had already returned to the intact app without an upload.

At resumption the app showed Cover saved; independent hosted readback confirmed one attached private PNG, 330203 bytes. Initial confirmation itself was not repeated or attributed to this resumed run. Force-stop/restart restored the administrator session; reopening Course cover fetched and displayed the persisted image without selecting it again.

Main then selected the same controlled logo again, confirmed Replace course cover, and verified two distinct immutable object paths: old retired, new attached/current, each 330203 bytes. Confirmed removal cleared the preview/reference and retired the second object. Before cleanup, a scoped ledger inventory confirmed only these two test assets were eligible; no unrelated assets existed. Confirmed bounded cleanup reported 2 cleaned, 0 failed, 2 attempted. Independent database readback confirmed cover_path NULL, two cleaned tombstones and zero matching storage.objects rows. Binary deletion used the app's Storage API, not SQL DELETE. Uploaded test copies are permanently removed; the original repository/phone input logo remains available.

Finally main soft-deleted the course again through its confirmation dialog. Settled default list showed no content; hosted readback confirmed archived, recoverably deleted and no cover. The course/session records remain recoverable, and no acceptance content was published. Owner login remained intact.

Evidence under E:/Android-prerequisites-Summit/: sea-cover-resume-current.png, sea-cover-restart-ready.png, sea-cover-restart-list.png, sea-cover-downloaded-restart.png, sea-cover-replace-picker.png, sea-cover-replace-selected.png, sea-cover-replace-confirm.png, sea-cover-replace-result.png, sea-cover-remove-confirm.png, sea-cover-removed.png, sea-cover-clean-confirm.png, sea-cover-clean-result.png, sea-cover-final-delete-confirm.png and sea-cover-final-hidden.png. Local screenshots are not committed.

This accepts the administrator debug-build binary workflow only, not student RLS over HTTP, iOS, concurrent edits, release signing or production readiness.
